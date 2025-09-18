//
//  DeviceMonitor.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import SwiftSnmpKit

struct DeviceData: Sendable {
    let deviceIndex: Int
    let label: String
    var uploadSpeed: Double = 0.0
    var downloadSpeed: Double = 0.0
    var formattedUploadSpeed: (value: String, unit: String) = ("-", "-")
    var formattedDownloadSpeed: (value: String, unit: String) = ("-", "-")
    var latency: Double? = nil
    var formattedLatency: String = "-"
    var errorMessage: String? = nil
    var availableInterfaces: [NetworkInterface] = []
    var isDiscoveringInterfaces = false
    
    init(deviceIndex: Int, label: String) {
        self.deviceIndex = deviceIndex
        self.label = label
    }
}

// MARK: - Circuit Breaker Implementation

private struct CircuitBreaker {
    enum State {
        case closed    // Normal operation
        case open      // Failing, skip requests
        case halfOpen  // Testing if service recovered
    }
    
    var state: State = .closed
    var failureCount = 0
    var lastFailureTime: Date?
    var nextRetryTime: Date?
    
    // Configuration
    let failureThreshold = 5
    let recoveryTimeInterval: TimeInterval = 30.0 // 30 seconds
    let maxBackoffInterval: TimeInterval = 300.0  // 5 minutes
    
    mutating func recordSuccess() {
        state = .closed
        failureCount = 0
        lastFailureTime = nil
        nextRetryTime = nil
    }
    
    mutating func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
            // Calculate exponential backoff
            let backoffInterval = min(
                recoveryTimeInterval * pow(2.0, Double(min(failureCount - failureThreshold, 6))),
                maxBackoffInterval
            )
            nextRetryTime = Date().addingTimeInterval(backoffInterval)
        }
    }
    
    mutating func canAttemptRequest() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            guard let nextRetry = nextRetryTime, Date() >= nextRetry else {
                return false
            }
            // Transition to half-open for testing
            state = .halfOpen
            return true
        case .halfOpen:
            return true
        }
    }
    
    func getBackoffDelay() -> TimeInterval? {
        guard let nextRetry = nextRetryTime else { return nil }
        let delay = nextRetry.timeIntervalSinceNow
        return delay > 0 ? delay : nil
    }
}

final class DeviceMonitor: Sendable {
    let deviceIndex: Int
    let host: String
    let community: String
    let port: Int
    let label: String
    let interfaceName: String
    let pingHost: String
    
    // Use actors or locks for thread safety
    private let lock = NSLock()
    private var _interfaceIndex: Int?
    private var _lastInOctets: UInt64?
    private var _lastOutOctets: UInt64?
    private var _lastTimestamp: Date?
    private var _circuitBreaker = CircuitBreaker()
    private var _lastInterfaceDiscovery: Date?
    private var _interfaceDiscoveryInterval: TimeInterval = 300.0 // 5 minutes
    
    // SNMP OIDs - try 64-bit counters for high speed interfaces
    private let ifHCInOctetsOID = "1.3.6.1.2.1.31.1.1.1.6"   // 64-bit counter
    private let ifHCOutOctetsOID = "1.3.6.1.2.1.31.1.1.1.10" // 64-bit counter
    
    // Smoothing
    private var _smoothedUploadSpeed: Double = 0.0
    private var _smoothedDownloadSpeed: Double = 0.0
    private let smoothingFactor: Double = 0.9
    
    // Thread-safe accessors with circuit breaker
    private var circuitBreaker: CircuitBreaker {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _circuitBreaker
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _circuitBreaker = newValue
        }
    }
    
    private var lastInterfaceDiscovery: Date? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastInterfaceDiscovery
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastInterfaceDiscovery = newValue
        }
    }
    
    private var interfaceIndex: Int? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _interfaceIndex
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _interfaceIndex = newValue
        }
    }
    
    private var lastInOctets: UInt64? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastInOctets
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastInOctets = newValue
        }
    }
    
    private var lastOutOctets: UInt64? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastOutOctets
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastOutOctets = newValue
        }
    }
    
    private var lastTimestamp: Date? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastTimestamp
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastTimestamp = newValue
        }
    }
    
    private var smoothedUploadSpeed: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _smoothedUploadSpeed
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _smoothedUploadSpeed = newValue
        }
    }
    
    private var smoothedDownloadSpeed: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _smoothedDownloadSpeed
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _smoothedDownloadSpeed = newValue
        }
    }
    
    init(deviceIndex: Int, host: String, community: String, port: Int, label: String, interfaceName: String, pingHost: String) {
        self.deviceIndex = deviceIndex
        self.host = host
        self.community = community
        self.port = port
        self.label = label
        self.interfaceName = interfaceName
        self.pingHost = pingHost
    }
    
    // MARK: - Optimized Interface Discovery using SNMPManager
    
    func discoverInterfaces(using snmpManager: SNMPManager = SNMPManager.shared, taskId: UUID = UUID()) async throws -> [NetworkInterface] {
        DebugLogger.logNetwork("===== Starting interface discovery for \(label) =====")
        
        // Use centralized SNMP manager with rate limiting
        let ifNames = try await snmpManager.performSnmpWalk(host: host, community: community, oid: "1.3.6.1.2.1.31.1.1.1.1", taskId: taskId)
        let ifDescr = try await snmpManager.performSnmpWalk(host: host, community: community, oid: "1.3.6.1.2.1.2.2.1.2", taskId: taskId)
        let ifOperStatus = try await snmpManager.performSnmpWalk(host: host, community: community, oid: "1.3.6.1.2.1.2.2.1.8", taskId: taskId)
        
        var interfaces: [NetworkInterface] = []
        
        // Create a set of all interface indices we've seen
        var allIndices = Set<Int>()
        allIndices.formUnion(ifNames.keys)
        allIndices.formUnion(ifDescr.keys)
        allIndices.formUnion(ifOperStatus.keys)
        
        DebugLogger.logNetwork("Found interface indices: \(Array(allIndices).sorted())")
        
        for index in allIndices {
            let name = ifNames[index] ?? "Interface\(index)"
            let description = ifDescr[index] ?? name
            let operStatusValue = ifOperStatus[index] ?? "down"
            
            // Handle both textual and numeric status values
            let status: String
            if operStatusValue.lowercased() == "up" || operStatusValue == "1" {
                status = "Up"
            } else if operStatusValue.lowercased() == "down" || operStatusValue == "2" {
                status = "Down" 
            } else {
                switch operStatusValue.lowercased() {
                case "testing", "3":
                    status = "Testing"
                case "unknown", "4":
                    status = "Unknown"
                case "dormant", "5":
                    status = "Dormant"
                case "notpresent", "6":
                    status = "Not Present"
                case "lowerlayerdown", "7":
                    status = "Lower Layer Down"
                default:
                    status = "Unknown (\(operStatusValue))"
                }
            }
            
            let interface = NetworkInterface(
                index: index,
                name: name,
                description: description,
                operStatus: status
            )
            
            // Only filter out the real loopback and system interfaces
            let isLoopback = name == "lo" || name.hasPrefix("lo0") || name.contains("127.0.0.1")
            let isNull = name.hasPrefix("null")
            let isSystemInterface = name == "miireg" || name == "dummy0" || name.starts(with: "ifb")
            
            if !isLoopback && !isNull && !isSystemInterface {
                interfaces.append(interface)
                DebugLogger.logNetwork("Added interface \(index): \(name) (\(description)) - \(status)")
            }
        }
        
        // Sort interfaces: "Up" interfaces first, then by index
        let sortedInterfaces = interfaces.sorted { interface1, interface2 in
            if interface1.operStatus == "Up" && interface2.operStatus != "Up" {
                return true
            }
            if interface1.operStatus != "Up" && interface2.operStatus == "Up" {
                return false
            }
            return interface1.index < interface2.index
        }
        
        DebugLogger.logNetwork("Interface discovery completed for \(label), found \(sortedInterfaces.count) interfaces")
        return sortedInterfaces
    }
    
    // MARK: - Optimized Traffic Data Update with Circuit Breaker
    
    func updateTrafficData(availableInterfaces: [NetworkInterface], using snmpManager: SNMPManager = SNMPManager.shared, taskId: UUID = UUID()) async throws -> (upload: Double, download: Double, formattedUpload: (String, String), formattedDownload: (String, String)) {
        
        // Check circuit breaker before attempting request
        var currentCircuitBreaker = circuitBreaker
        
        guard currentCircuitBreaker.canAttemptRequest() else {
            if let backoffDelay = currentCircuitBreaker.getBackoffDelay() {
                DebugLogger.logNetwork("\(label) - Circuit breaker OPEN, retrying in \(Int(backoffDelay))s")
            }
            throw NetworkDiscoveryError.deviceUnreachable
        }
        
        // Check if we need to rediscover interfaces
        let shouldRediscoverInterfaces = shouldRediscoverInterfaces(availableInterfaces: availableInterfaces)
        if shouldRediscoverInterfaces {
            DebugLogger.logNetwork("\(label) - Interface rediscovery needed")
            throw NetworkDiscoveryError.interfaceNotFound
        }
        
        DebugLogger.logSNMP("\(label) - Starting traffic update (Circuit Breaker: \(currentCircuitBreaker.state))")
        
        // Ensure we have interface index
        if interfaceIndex == nil {
            if !interfaceName.isEmpty {
                if let interface = availableInterfaces.first(where: { $0.name == interfaceName }) {
                    interfaceIndex = interface.index
                    DebugLogger.logNetwork("\(label) - Found interface '\(interfaceName)' at index \(interface.index)")
                }
            }
            
            if interfaceIndex == nil {
                if let interface = availableInterfaces.first(where: { $0.operStatus == "Up" && $0.ipAddress != "N/A" }) {
                    interfaceIndex = interface.index
                    DebugLogger.logNetwork("\(label) - Auto-selected first UP interface: \(interface.name) (index \(interface.index))")
                } else if let interface = availableInterfaces.first(where: { $0.operStatus == "Up" }) {
                    interfaceIndex = interface.index
                    DebugLogger.logNetwork("\(label) - Auto-selected first UP interface (no IP check): \(interface.name) (index \(interface.index))")
                }
            }
            
            guard interfaceIndex != nil else {
                currentCircuitBreaker.recordFailure()
                circuitBreaker = currentCircuitBreaker
                DebugLogger.logError("\(label) - No suitable interface found")
                throw NetworkDiscoveryError.interfaceNotFound
            }
        }
        
        let inOid = "\(ifHCInOctetsOID).\(interfaceIndex!)"
        let outOid = "\(ifHCOutOctetsOID).\(interfaceIndex!)"
        
        do {
            // Use centralized SNMP manager
            let currentInOctets = try await snmpManager.performSnmpGet(host: host, community: community, oid: inOid, taskId: taskId)
            let currentOutOctets = try await snmpManager.performSnmpGet(host: host, community: community, oid: outOid, taskId: taskId)
            
            let now = Date()
            
            // Calculate speeds if we have previous data
            if let lastIn = lastInOctets,
               let lastOut = lastOutOctets,
               let lastTime = lastTimestamp {
                
                let timeDiff = now.timeIntervalSince(lastTime)
                
                // Minimum time difference to avoid division by very small numbers
                guard timeDiff > 2.0 else {
                    DebugLogger.logSNMP("\(label) - Time difference too small (\(timeDiff)s), skipping calculation")
                    return (smoothedUploadSpeed, smoothedDownloadSpeed, formatSpeed(smoothedUploadSpeed), formatSpeed(smoothedDownloadSpeed))
                }
                
                // Handle counter wraparound with validation
                let inDiff: UInt64
                let outDiff: UInt64
                
                if currentInOctets >= lastIn {
                    inDiff = currentInOctets - lastIn
                } else {
                    let wrappedDiff = (UInt64.max - lastIn) + currentInOctets
                    if wrappedDiff > 1_000_000_000_000 {
                        DebugLogger.logError("\(label) - Counter wraparound seems unreasonable, resetting")
                        lastInOctets = currentInOctets
                        lastOutOctets = currentOutOctets
                        lastTimestamp = now
                        return (0.0, 0.0, ("-", "-"), ("-", "-"))
                    }
                    inDiff = wrappedDiff
                }
                
                if currentOutOctets >= lastOut {
                    outDiff = currentOutOctets - lastOut
                } else {
                    let wrappedDiff = (UInt64.max - lastOut) + currentOutOctets
                    if wrappedDiff > 1_000_000_000_000 {
                        DebugLogger.logError("\(label) - Counter wraparound seems unreasonable, resetting")
                        lastInOctets = currentInOctets
                        lastOutOctets = currentOutOctets
                        lastTimestamp = now
                        return (0.0, 0.0, ("-", "-"), ("-", "-"))
                    }
                    outDiff = wrappedDiff
                }
                
                // Calculate bytes per second
                let downloadBps = Double(inDiff) / timeDiff
                let uploadBps = Double(outDiff) / timeDiff
                
                DebugLogger.logSNMP("\(label) - Calculated: Up=\(uploadBps) bytes/s, Down=\(downloadBps) bytes/s")
                
                // Sanity check - if speeds are unreasonably high, reset
                if downloadBps > 10_000_000_000 || uploadBps > 10_000_000_000 {
                    DebugLogger.logError("\(label) - Calculated speeds seem unreasonable, resetting")
                    lastInOctets = currentInOctets
                    lastOutOctets = currentOutOctets
                    lastTimestamp = now
                    smoothedUploadSpeed = 0.0
                    smoothedDownloadSpeed = 0.0
                    return (0.0, 0.0, ("-", "-"), ("-", "-"))
                }
                
                // Apply smoothing
                if smoothedUploadSpeed == 0.0 && smoothedDownloadSpeed == 0.0 {
                    smoothedUploadSpeed = uploadBps
                    smoothedDownloadSpeed = downloadBps
                } else {
                    smoothedUploadSpeed = (smoothingFactor * uploadBps) + 
                        ((1 - smoothingFactor) * smoothedUploadSpeed)
                    smoothedDownloadSpeed = (smoothingFactor * downloadBps) + 
                        ((1 - smoothingFactor) * smoothedDownloadSpeed)
                }
                
                // Store current values for next calculation
                lastInOctets = currentInOctets
                lastOutOctets = currentOutOctets
                lastTimestamp = now
                
                // Record success in circuit breaker
                currentCircuitBreaker.recordSuccess()
                circuitBreaker = currentCircuitBreaker
                
                return (smoothedUploadSpeed, smoothedDownloadSpeed, formatSpeed(smoothedUploadSpeed), formatSpeed(smoothedDownloadSpeed))
            } else {
                // First run - just store values
                DebugLogger.logSNMP("\(label) - First run, storing baseline")
                lastInOctets = currentInOctets
                lastOutOctets = currentOutOctets
                lastTimestamp = now
                
                // Record success in circuit breaker
                currentCircuitBreaker.recordSuccess()
                circuitBreaker = currentCircuitBreaker
                
                return (0.0, 0.0, ("-", "-"), ("-", "-"))
            }
            
        } catch {
            // Record failure in circuit breaker
            currentCircuitBreaker.recordFailure()
            circuitBreaker = currentCircuitBreaker
            
            DebugLogger.logError("\(label) - Traffic update error, circuit breaker failures: \(currentCircuitBreaker.failureCount)", error: error)
            throw error
        }
    }
    
    // MARK: - Interface Rediscovery Logic
    
    private func shouldRediscoverInterfaces(availableInterfaces: [NetworkInterface]) -> Bool {
        // If no interfaces available, always rediscover
        if availableInterfaces.isEmpty {
            return true
        }
        
        // If we have an interface index but it's not in available interfaces, rediscover
        if let currentIndex = interfaceIndex,
           !availableInterfaces.contains(where: { $0.index == currentIndex }) {
            return true
        }
        
        // Periodic rediscovery
        if let lastDiscovery = lastInterfaceDiscovery {
            return Date().timeIntervalSince(lastDiscovery) > _interfaceDiscoveryInterval
        }
        
        return false
    }
    
    // MARK: - Latency Update
    
    func updateLatency(taskId: UUID = UUID()) async -> (latency: Double?, formatted: String) {
        let host = pingHost.isEmpty ? "8.8.8.8" : pingHost
        
        do {
            let result = try await withThrowingTaskGroup(of: (Double?, String).self) { group in
                group.addTask {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                    process.arguments = ["-c", "1", "-t", "5", host]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: 8_000_000_000)
                        process.terminate()
                    }
                    
                    try process.run()
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        if let timeRange = output.range(of: "time=") {
                            let timeString = String(output[timeRange.upperBound...])
                            if let timeEnd = timeString.firstIndex(of: " "),
                               let latencyValue = Double(String(timeString[..<timeEnd])) {
                                return (latencyValue, String(format: "%.1f", latencyValue))
                            }
                        }
                    }
                    return (nil as Double?, "-")
                }
                
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            return result
            
        } catch {
            return (nil as Double?, "-")
        }
    }

    func resetState() {
        lock.lock()
        defer { lock.unlock() }
        _lastInOctets = nil
        _lastOutOctets = nil
        _lastTimestamp = nil
        _smoothedUploadSpeed = 0.0
        _smoothedDownloadSpeed = 0.0
        _circuitBreaker = CircuitBreaker()
        _lastInterfaceDiscovery = nil
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let config = NetworkConfiguration.shared
        
        // Reasonable sanity check
        guard bytesPerSecond < 1_000_000_000_000 else {
            return ("ERR", "?/s")
        }
        
        let formattedResult: (value: String, unit: String)
        
        switch config.speedDisplayUnit {
        case .bits:
            // Convert bytes to bits per second
            let bitsPerSecond = bytesPerSecond * 8
            
            if bitsPerSecond < 1_000 {
                formattedResult = (String(format: "%.0f", bitsPerSecond), "bps")
            } else if bitsPerSecond < 1_000_000 {
                let kbps = bitsPerSecond / 1_000
                formattedResult = (String(format: "%.1f", kbps), "Kbps")
            } else if bitsPerSecond < 1_000_000_000 {
                let mbps = bitsPerSecond / 1_000_000
                formattedResult = (String(format: "%.1f", mbps), "Mbps")
            } else {
                let gbps = bitsPerSecond / 1_000_000_000
                formattedResult = (String(format: "%.2f", gbps), "Gbps")
            }
            
        case .bytes:
            if bytesPerSecond < 1_000 {
                formattedResult = (String(format: "%.0f", bytesPerSecond), "B/s")
            } else if bytesPerSecond < 1_000_000 {
                let kbs = bytesPerSecond / 1_000
                formattedResult = (String(format: "%.1f", kbs), "KB/s")
            } else if bytesPerSecond < 1_000_000_000 {
                let mbs = bytesPerSecond / 1_000_000
                formattedResult = (String(format: "%.1f", mbs), "MB/s")
            } else {
                let gbs = bytesPerSecond / 1_000_000_000
                formattedResult = (String(format: "%.2f", gbs), "GB/s")
            }
        }
        
        let cleanedValue = formattedResult.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanedValue, formattedResult.unit)
    }
}