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
    var packetsSent: Int = 0
    var packetsReceived: Int = 0
    var packetLossPercentage: Double = 0.0
    var formattedPacketLoss: String = "-"
    var errorMessage: String? = nil
    var availableInterfaces: [NetworkInterface] = []
    var isDiscoveringInterfaces = false
    
    // New fields for interface speed and utilization
    var interfaceSpeed: UInt64? = nil // Interface speed in bps
    var formattedInterfaceSpeed: String = "-"
    var uploadUtilization: Double? = nil // Upload utilization percentage (0-100)
    var downloadUtilization: Double? = nil // Download utilization percentage (0-100)
    
    init(deviceIndex: Int, label: String) {
        self.deviceIndex = deviceIndex
        self.label = label
    }
}

// MARK: - Circuit Breaker Implementation

private struct CircuitBreaker: Sendable {
    enum State: Sendable {
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
    
    nonisolated init() {
        self.state = .closed
        self.failureCount = 0
        self.lastFailureTime = nil
        self.nextRetryTime = nil
    }
    
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

// MARK: - Device Monitor State Actor

private actor DeviceMonitorState {
    var interfaceIndex: Int?
    var lastInOctets: UInt64?
    var lastOutOctets: UInt64?
    var lastTimestamp: Date?
    var circuitBreaker: CircuitBreaker
    var lastInterfaceDiscovery: Date?
    var cachedInterfaces: [NetworkInterface] = []
    var smoothedUploadSpeed: Double = 0.0
    var smoothedDownloadSpeed: Double = 0.0
    
    init() {
        self.circuitBreaker = CircuitBreaker()
    }
    
    let interfaceDiscoveryInterval: TimeInterval = 300.0 // 5 minutes
    let interfaceCacheInterval: TimeInterval = 60.0 // 1 minute cache
    
    func getCircuitBreaker() -> CircuitBreaker {
        return circuitBreaker
    }
    
    func updateCircuitBreaker(_ newBreaker: CircuitBreaker) {
        circuitBreaker = newBreaker
    }
    
    func getCachedInterfaces() -> (interfaces: [NetworkInterface], lastDiscovery: Date?, cacheInterval: TimeInterval) {
        return (cachedInterfaces, lastInterfaceDiscovery, interfaceCacheInterval)
    }
    
    func updateCache(_ interfaces: [NetworkInterface]) {
        cachedInterfaces = interfaces
        lastInterfaceDiscovery = Date()
    }
    
    func getTrafficState() -> (lastIn: UInt64?, lastOut: UInt64?, lastTime: Date?, smoothedUp: Double, smoothedDown: Double) {
        return (lastInOctets, lastOutOctets, lastTimestamp, smoothedUploadSpeed, smoothedDownloadSpeed)
    }
    
    func updateTrafficState(inOctets: UInt64, outOctets: UInt64, timestamp: Date, smoothedUp: Double, smoothedDown: Double) {
        lastInOctets = inOctets
        lastOutOctets = outOctets
        lastTimestamp = timestamp
        smoothedUploadSpeed = smoothedUp
        smoothedDownloadSpeed = smoothedDown
    }
    
    func resetTrafficState() {
        lastInOctets = nil
        lastOutOctets = nil
        lastTimestamp = nil
        smoothedUploadSpeed = 0.0
        smoothedDownloadSpeed = 0.0
    }
    
    // Uptime tracking for reboot detection
    var lastKnownUptime: UInt64?
    var rebootDetectedAt: Date?
    
    /// Returns true if a reboot was detected (uptime decreased).
    func checkAndUpdateUptime(_ centiseconds: UInt64) -> Bool {
        let rebootDetected: Bool
        if let last = lastKnownUptime, centiseconds < last {
            rebootDetected = true
            rebootDetectedAt = Date()
        } else {
            rebootDetected = false
        }
        lastKnownUptime = centiseconds
        return rebootDetected
    }
    
    func resetAll() {
        interfaceIndex = nil
        lastInOctets = nil
        lastOutOctets = nil
        lastTimestamp = nil
        smoothedUploadSpeed = 0.0
        smoothedDownloadSpeed = 0.0
        circuitBreaker = CircuitBreaker()
        lastInterfaceDiscovery = nil
        cachedInterfaces = []
        lastKnownUptime = nil
        rebootDetectedAt = nil
    }
    
    func getInterfaceIndex() -> Int? {
        return interfaceIndex
    }
    
    func setInterfaceIndex(_ index: Int?) {
        interfaceIndex = index
    }
    
    func shouldRediscoverInterfaces(availableInterfaces: [NetworkInterface]) -> Bool {
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
            return Date().timeIntervalSince(lastDiscovery) > interfaceDiscoveryInterval
        }
        
        return false
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
    
    // Use actor for thread-safe state management
    private let state: DeviceMonitorState
    
    // SNMP OIDs - try 64-bit counters for high speed interfaces
    private let ifHCInOctetsOID = "1.3.6.1.2.1.31.1.1.1.6"   // 64-bit counter
    private let ifHCOutOctetsOID = "1.3.6.1.2.1.31.1.1.1.10" // 64-bit counter
    
    // Interface speed and status OIDs
    private let ifHighSpeedOID = "1.3.6.1.2.1.31.1.1.1.15"   // Interface speed in Mbps
    private let ifSpeedOID = "1.3.6.1.2.1.2.2.1.5"           // Interface speed in bps (for slower interfaces)
    
    // System OIDs
    private let sysUptimeOID = "1.3.6.1.2.1.1.3.0"           // sysUpTime in centiseconds (TimeTicks)
    
    // Smoothing
    private let smoothingFactor: Double = 0.7  // Reduced from 0.9 for more responsive updates
    
    init(deviceIndex: Int, host: String, community: String, port: Int, label: String, interfaceName: String, pingHost: String) {
        self.deviceIndex = deviceIndex
        self.host = host
        self.community = community
        self.port = port
        self.label = label
        self.interfaceName = interfaceName
        self.pingHost = pingHost
        self.state = DeviceMonitorState()
    }
    
    // MARK: - Optimized Interface Discovery using SNMPManager
    
    func discoverInterfaces(using snmpManager: SNMPManager = SNMPManager.shared, updateInterval: TimeInterval = 2.0, taskId: UUID = UUID()) async throws -> [NetworkInterface] {
        DebugLogger.logNetwork("===== Starting interface discovery for \(label) =====")
        
        // Check cache first
        let (cachedInterfaces, lastDiscovery, cacheInterval) = await state.getCachedInterfaces()
        
        if !cachedInterfaces.isEmpty, let lastDiscovery = lastDiscovery {
            let timeSinceLastDiscovery = Date().timeIntervalSince(lastDiscovery)
            if timeSinceLastDiscovery < cacheInterval {
                DebugLogger.logNetwork("Using cached interfaces for \(label) (age: \(Int(timeSinceLastDiscovery))s)")
                return cachedInterfaces
            }
        }
        
        // Use concurrent SNMP walks for faster discovery
        // Each task gets its own UUID so process tracking and cancellation work correctly
        let (ifNames, ifDescr, ifOperStatus) = try await withThrowingTaskGroup(of: (String, [Int: String]).self, returning: ([Int: String], [Int: String], [Int: String]).self) { group in
            
            group.addTask {
                let result = try await snmpManager.performSnmpWalk(host: self.host, community: self.community, oid: "1.3.6.1.2.1.31.1.1.1.1", updateInterval: updateInterval, taskId: UUID())
                return ("names", result)
            }
            
            group.addTask {
                let result = try await snmpManager.performSnmpWalk(host: self.host, community: self.community, oid: "1.3.6.1.2.1.2.2.1.2", updateInterval: updateInterval, taskId: UUID())
                return ("descr", result)
            }
            
            group.addTask {
                let result = try await snmpManager.performSnmpWalk(host: self.host, community: self.community, oid: "1.3.6.1.2.1.2.2.1.8", updateInterval: updateInterval, taskId: UUID())
                return ("status", result)
            }
            
            var names: [Int: String] = [:]
            var descr: [Int: String] = [:]
            var status: [Int: String] = [:]
            
            for try await (type, result) in group {
                switch type {
                case "names": names = result
                case "descr": descr = result
                case "status": status = result
                default: break
                }
            }
            
            return (names, descr, status)
        }
        
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
        
        // Update cache
        await state.updateCache(sortedInterfaces)
        
        return sortedInterfaces
    }
    
    // MARK: - Optimized Traffic Data Update with Circuit Breaker
    
    func updateTrafficData(availableInterfaces: [NetworkInterface], using snmpManager: SNMPManager = SNMPManager.shared, updateInterval: TimeInterval = 2.0, taskId: UUID = UUID()) async throws -> (upload: Double, download: Double, formattedUpload: (String, String), formattedDownload: (String, String)) {
        
        // Check circuit breaker before attempting request
        var currentCircuitBreaker = await state.getCircuitBreaker()
        
        guard currentCircuitBreaker.canAttemptRequest() else {
            if let backoffDelay = currentCircuitBreaker.getBackoffDelay() {
                DebugLogger.logNetwork("\(label) - Circuit breaker OPEN, retrying in \(Int(backoffDelay))s")
            }
            throw NetworkDiscoveryError.deviceUnreachable
        }
        
        // Check if we need to rediscover interfaces
        let shouldRediscoverInterfaces = await state.shouldRediscoverInterfaces(availableInterfaces: availableInterfaces)
        if shouldRediscoverInterfaces {
            DebugLogger.logNetwork("\(label) - Interface rediscovery needed")
            throw NetworkDiscoveryError.interfaceNotFound
        }
        
        DebugLogger.logSNMP("\(label) - Starting traffic update (Circuit Breaker: \(currentCircuitBreaker.state))")
        
        // Ensure we have interface index
        var interfaceIndex = await state.getInterfaceIndex()
        if interfaceIndex == nil {
            if !interfaceName.isEmpty {
                if let interface = availableInterfaces.first(where: { $0.name == interfaceName }) {
                    interfaceIndex = interface.index
                    await state.setInterfaceIndex(interface.index)
                    DebugLogger.logNetwork("\(label) - Found interface '\(interfaceName)' at index \(interface.index)")
                }
            }
            
            if interfaceIndex == nil {
                if let interface = availableInterfaces.first(where: { $0.operStatus == "Up" && $0.ipAddress != "N/A" }) {
                    interfaceIndex = interface.index
                    await state.setInterfaceIndex(interface.index)
                    DebugLogger.logNetwork("\(label) - Auto-selected first UP interface: \(interface.name) (index \(interface.index))")
                } else if let interface = availableInterfaces.first(where: { $0.operStatus == "Up" }) {
                    interfaceIndex = interface.index
                    await state.setInterfaceIndex(interface.index)
                    DebugLogger.logNetwork("\(label) - Auto-selected first UP interface (no IP check): \(interface.name) (index \(interface.index))")
                }
            }
            
            guard interfaceIndex != nil else {
                currentCircuitBreaker.recordFailure()
                await state.updateCircuitBreaker(currentCircuitBreaker)
                DebugLogger.logError("\(label) - No suitable interface found")
                throw NetworkDiscoveryError.interfaceNotFound
            }
        }
        
        let inOid = "\(ifHCInOctetsOID).\(interfaceIndex!)"
        let outOid = "\(ifHCOutOctetsOID).\(interfaceIndex!)"
        
        do {
            // Fetch in/out counters concurrently - each gets its own UUID for correct process tracking
            async let inResult = snmpManager.performSnmpGet(host: host, community: community, oid: inOid, updateInterval: updateInterval, taskId: taskId)
            async let outResult = snmpManager.performSnmpGet(host: host, community: community, oid: outOid, updateInterval: updateInterval, taskId: UUID())
            let (currentInOctets, currentOutOctets) = try await (inResult, outResult)
            
            let now = Date()
            
            // Get previous state
            let (lastIn, lastOut, lastTime, smoothedUp, smoothedDown) = await state.getTrafficState()
            
            // Calculate speeds if we have previous data
            if let lastIn = lastIn,
               let lastOut = lastOut,
               let lastTime = lastTime {
                
                let timeDiff = now.timeIntervalSince(lastTime)
                
                // Get speed display unit from configuration
                let speedDisplayUnit = await getSpeedDisplayUnit()
                
                // Minimum time difference to avoid division by very small numbers
                guard timeDiff > 0.5 else {
                    DebugLogger.logSNMP("\(label) - Time difference too small (\(timeDiff)s), skipping calculation")
                    return (smoothedUp, smoothedDown, formatSpeed(smoothedUp, unit: speedDisplayUnit), formatSpeed(smoothedDown, unit: speedDisplayUnit))
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
                        await state.updateTrafficState(inOctets: currentInOctets, outOctets: currentOutOctets, timestamp: now, smoothedUp: 0.0, smoothedDown: 0.0)
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
                        await state.updateTrafficState(inOctets: currentInOctets, outOctets: currentOutOctets, timestamp: now, smoothedUp: 0.0, smoothedDown: 0.0)
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
                    await state.updateTrafficState(inOctets: currentInOctets, outOctets: currentOutOctets, timestamp: now, smoothedUp: 0.0, smoothedDown: 0.0)
                    return (0.0, 0.0, ("-", "-"), ("-", "-"))
                }
                
                // Apply smoothing
                let newSmoothedUpload: Double
                let newSmoothedDownload: Double
                
                if smoothedUp == 0.0 && smoothedDown == 0.0 {
                    newSmoothedUpload = uploadBps
                    newSmoothedDownload = downloadBps
                } else {
                    newSmoothedUpload = (smoothingFactor * uploadBps) + 
                        ((1 - smoothingFactor) * smoothedUp)
                    newSmoothedDownload = (smoothingFactor * downloadBps) + 
                        ((1 - smoothingFactor) * smoothedDown)
                }
                
                // Store current values for next calculation
                await state.updateTrafficState(inOctets: currentInOctets, outOctets: currentOutOctets, timestamp: now, smoothedUp: newSmoothedUpload, smoothedDown: newSmoothedDownload)
                
                // Record success in circuit breaker
                currentCircuitBreaker.recordSuccess()
                await state.updateCircuitBreaker(currentCircuitBreaker)
                
                return (newSmoothedUpload, newSmoothedDownload, formatSpeed(newSmoothedUpload, unit: speedDisplayUnit), formatSpeed(newSmoothedDownload, unit: speedDisplayUnit))
            } else {
                // First run - just store values
                DebugLogger.logSNMP("\(label) - First run, storing baseline")
                await state.updateTrafficState(inOctets: currentInOctets, outOctets: currentOutOctets, timestamp: now, smoothedUp: 0.0, smoothedDown: 0.0)
                
                // Record success in circuit breaker
                currentCircuitBreaker.recordSuccess()
                await state.updateCircuitBreaker(currentCircuitBreaker)
                
                return (0.0, 0.0, ("-", "-"), ("-", "-"))
            }
            
        } catch {
            // Record failure in circuit breaker only if not a cancellation
            if !(error is CancellationError) {
                currentCircuitBreaker.recordFailure()
                await state.updateCircuitBreaker(currentCircuitBreaker)
                
                DebugLogger.logError("\(label) - Traffic update error, circuit breaker failures: \(currentCircuitBreaker.failureCount)", error: error)
            } else {
                DebugLogger.logNetwork("\(label) - Traffic update cancelled")
            }
            throw error
        }
    }
    
    // MARK: - Interface Rediscovery Logic
    
    private func shouldRediscoverInterfaces(availableInterfaces: [NetworkInterface]) async -> Bool {
        return await state.shouldRediscoverInterfaces(availableInterfaces: availableInterfaces)
    }
    
    // MARK: - System Uptime
    
    /// Fetches sysUpTime from the device. Returns formatted uptime string and whether a reboot was detected.
    func fetchSysUptime(using snmpManager: SNMPManager = SNMPManager.shared, updateInterval: TimeInterval = 2.0) async -> (formatted: String, rebootDetected: Bool) {
        do {
            let raw = try await snmpManager.performSnmpGetString(host: host, community: community, oid: sysUptimeOID, updateInterval: updateInterval, taskId: UUID())
            DebugLogger.logSNMP("\(label) - sysUpTime raw: '\(raw)'")
            // Detect SNMP error responses (device doesn't support OID)
            let lower = raw.lowercased()
            guard !lower.contains("no such") && !lower.contains("error") && !lower.contains("unknown") else {
                DebugLogger.logSNMP("\(label) - sysUpTime OID not supported by device: \(raw)")
                return ("-", false)
            }
            let centiseconds = parseTimeTicks(raw)
            guard centiseconds > 0 else {
                DebugLogger.logSNMP("\(label) - sysUpTime parsed to 0, raw was: '\(raw)'")
                return ("-", false)
            }
            let rebootDetected = await state.checkAndUpdateUptime(centiseconds)
            DebugLogger.logSNMP("\(label) - sysUpTime: \(centiseconds)cs → \(formatUptime(centiseconds))")
            return (formatUptime(centiseconds), rebootDetected)
        } catch {
            DebugLogger.logSNMP("\(label) - sysUpTime fetch failed: \(error)")
            return ("-", false)
        }
    }
    
    /// Parses snmpget TimeTicks output into centiseconds.
    /// Handles plain integers, "H:MM:SS.cc", "D day(s), H:MM:SS.cc",
    /// and "Timeticks: (12345) H:MM:SS.cc" (when -Oqv flag is ignored by some agents).
    private func parseTimeTicks(_ s: String) -> UInt64 {
        var rest = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip "Timeticks: (NNN) " prefix if present
        if rest.lowercased().hasPrefix("timeticks:") {
            if let parenClose = rest.range(of: ") ") {
                rest = String(rest[parenClose.upperBound...])
            }
        }
        
        // Plain integer (raw centiseconds) — returned by some net-snmp versions
        if let raw = UInt64(rest) { return raw }
        
        // "D day(s), H:MM:SS.cc" format
        var days: UInt64 = 0
        if rest.contains(" day") {
            if let dayRange = rest.range(of: " day"),
               let commaRange = rest.range(of: ", ") {
                days = UInt64(String(rest[rest.startIndex..<dayRange.lowerBound]).trimmingCharacters(in: .whitespaces)) ?? 0
                rest = String(rest[commaRange.upperBound...])
            }
        }
        
        // "H:MM:SS.cc" format
        let timeParts = rest.components(separatedBy: ":")
        guard timeParts.count == 3 else { return days * 8_640_000 }
        let h = UInt64(timeParts[0]) ?? 0
        let m = UInt64(timeParts[1]) ?? 0
        let secParts = timeParts[2].components(separatedBy: ".")
        let sec = UInt64(secParts[0]) ?? 0
        let cs  = secParts.count > 1 ? (UInt64(secParts[1]) ?? 0) : 0
        
        return days * 8_640_000 + h * 360_000 + m * 6_000 + sec * 100 + cs
    }
    
    private func formatUptime(_ centiseconds: UInt64) -> String {
        let totalSeconds = centiseconds / 100
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Latency and Packet Loss Update
    
    func updateLatency(taskId: UUID = UUID()) async -> (latency: Double?, formatted: String, packetsSent: Int, packetsReceived: Int, packetLoss: Double, formattedLoss: String) {
        let host = pingHost.isEmpty ? "8.8.8.8" : pingHost
        
        do {
            let result = try await withThrowingTaskGroup(of: (Double?, String, Int, Int, Double, String).self) { group in
                group.addTask {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                    // 1 packet, 2s timeout — fast enough for 1s update interval
                    process.arguments = ["-c", "1", "-t", "2", host]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: 4_000_000_000)
                        process.terminate()
                    }
                    
                    try process.run()
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        
                        var latencyValue: Double? = nil
                        var packetsSent = 0
                        var packetsReceived = 0
                        var lossPercentage = 0.0
                        
                        // Parse latency from lines like "time=14.2 ms"
                        if let timeRange = output.range(of: "time=") {
                            let timeString = String(output[timeRange.upperBound...])
                            if let timeEnd = timeString.firstIndex(of: " "),
                               let latency = Double(String(timeString[..<timeEnd])) {
                                latencyValue = latency
                            }
                        }
                        
                        // Parse packet statistics from line like "3 packets transmitted, 3 packets received, 0.0% packet loss"
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            // Look for the statistics line
                            if line.contains("packets transmitted") {
                                // Pattern: "X packets transmitted, Y packets received"
                                let components = line.components(separatedBy: ",")
                                
                                // Extract transmitted count
                                if let transmittedPart = components.first {
                                    let words = transmittedPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                                    if let count = words.first, let transmitted = Int(count) {
                                        packetsSent = transmitted
                                    }
                                }
                                
                                // Extract received count
                                if components.count > 1 {
                                    let receivedPart = components[1]
                                    let words = receivedPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                                    if let count = words.first, let received = Int(count) {
                                        packetsReceived = received
                                    }
                                }
                                
                                // Extract packet loss percentage
                                if components.count > 2 {
                                    let lossPart = components[2]
                                    if let percentRange = lossPart.range(of: "%") {
                                        let lossString = lossPart[..<percentRange.lowerBound].trimmingCharacters(in: .whitespaces)
                                        if let loss = Double(lossString) {
                                            lossPercentage = loss
                                        }
                                    }
                                }
                                break
                            }
                        }
                        
                        let formattedLatency = latencyValue.map { String(format: "%.1f", $0) } ?? "-"
                        let formattedLoss = packetsSent > 0 ? String(format: "%.0f%%", lossPercentage) : "-"
                        
                        return (latencyValue, formattedLatency, packetsSent, packetsReceived, lossPercentage, formattedLoss)
                    }
                    return (nil as Double?, "-", 0, 0, 0.0, "-")
                }
                
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            return result
            
        } catch {
            return (nil as Double?, "-", 0, 0, 0.0, "-")
        }
    }

    // MARK: - Interface Speed and Utilization
    
    func updateInterfaceSpeedAndUtilization(currentUploadSpeed: Double, currentDownloadSpeed: Double, using snmpManager: SNMPManager = SNMPManager.shared, updateInterval: TimeInterval = 2.0, taskId: UUID = UUID()) async throws -> (speed: UInt64, formattedSpeed: String, uploadUtil: Double, downloadUtil: Double) {
        
        // Get interface index - must have interfaces discovered first
        guard let interfaceIndex = await state.getInterfaceIndex() else {
            DebugLogger.logSNMP("\(label) - No interface index set, skipping speed/utilization update")
            throw NetworkDiscoveryError.interfaceNotFound
        }
        
        DebugLogger.logSNMP("\(label) - Querying interface speed for index \(interfaceIndex)")
        
        // Try to get high-speed interface speed first (for Gigabit+ interfaces)
        let highSpeedOid = "\(ifHighSpeedOID).\(interfaceIndex)"
        
        do {
            let speedMbps = try await snmpManager.performSnmpGet(host: host, community: community, oid: highSpeedOid, updateInterval: updateInterval, taskId: taskId)
            
            guard speedMbps > 0 else {
                DebugLogger.logSNMP("\(label) - High-speed OID returned 0, trying regular speed OID")
                // If high-speed is 0, try regular speed OID
                return try await getRegularInterfaceSpeed(interfaceIndex: interfaceIndex, currentUploadSpeed: currentUploadSpeed, currentDownloadSpeed: currentDownloadSpeed, using: snmpManager, updateInterval: updateInterval, taskId: taskId)
            }
            
            let speedBps = speedMbps * 1_000_000 // Convert Mbps to bps
            let formattedSpeed = formatInterfaceSpeed(speedBps)
            
            // Calculate utilization percentages
            let uploadUtil = calculateUtilization(currentSpeed: currentUploadSpeed, maxSpeed: Double(speedBps))
            let downloadUtil = calculateUtilization(currentSpeed: currentDownloadSpeed, maxSpeed: Double(speedBps))
            
            DebugLogger.logSNMP("\(label) - Interface speed: \(formattedSpeed), Upload util: \(String(format: "%.1f%%", uploadUtil)), Download util: \(String(format: "%.1f%%", downloadUtil))")
            
            return (speedBps, formattedSpeed, uploadUtil, downloadUtil)
            
        } catch {
            DebugLogger.logSNMP("\(label) - High-speed OID failed, trying regular speed OID")
            // Fall back to regular speed OID
            return try await getRegularInterfaceSpeed(interfaceIndex: interfaceIndex, currentUploadSpeed: currentUploadSpeed, currentDownloadSpeed: currentDownloadSpeed, using: snmpManager, updateInterval: updateInterval, taskId: taskId)
        }
    }
    
    private func getRegularInterfaceSpeed(interfaceIndex: Int, currentUploadSpeed: Double, currentDownloadSpeed: Double, using snmpManager: SNMPManager, updateInterval: TimeInterval, taskId: UUID) async throws -> (speed: UInt64, formattedSpeed: String, uploadUtil: Double, downloadUtil: Double) {
        let speedOid = "\(ifSpeedOID).\(interfaceIndex)"
        
        let speedBps = try await snmpManager.performSnmpGet(host: host, community: community, oid: speedOid, updateInterval: updateInterval, taskId: taskId)
        
        guard speedBps > 0 else {
            throw NetworkDiscoveryError.invalidResponse
        }
        
        let formattedSpeed = formatInterfaceSpeed(speedBps)
        
        // Calculate utilization percentages
        let uploadUtil = calculateUtilization(currentSpeed: currentUploadSpeed, maxSpeed: Double(speedBps))
        let downloadUtil = calculateUtilization(currentSpeed: currentDownloadSpeed, maxSpeed: Double(speedBps))
        
        DebugLogger.logSNMP("\(label) - Interface speed: \(formattedSpeed), Upload util: \(String(format: "%.1f%%", uploadUtil)), Download util: \(String(format: "%.1f%%", downloadUtil))")
        
        return (speedBps, formattedSpeed, uploadUtil, downloadUtil)
    }
    
    private func calculateUtilization(currentSpeed: Double, maxSpeed: Double) -> Double {
        guard maxSpeed > 0 else { return 0.0 }
        
        // Current speed is in bytes per second, convert to bits per second
        let currentBps = currentSpeed * 8
        
        // Calculate percentage
        let utilization = (currentBps / maxSpeed) * 100.0
        
        // Clamp to 0-100
        return min(max(utilization, 0.0), 100.0)
    }
    
    private func formatInterfaceSpeed(_ speedBps: UInt64) -> String {
        let bps = Double(speedBps)
        
        if bps >= 1_000_000_000 {
            return String(format: "%.1f Gbps", bps / 1_000_000_000)
        } else if bps >= 1_000_000 {
            return String(format: "%.0f Mbps", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.0f Kbps", bps / 1_000)
        } else {
            return "\(speedBps) bps"
        }
    }
    
    
    func resetState() {
        Task {
            await state.resetAll()
        }
    }
    
    private func getSpeedDisplayUnit() async -> SpeedDisplayUnit {
        await MainActor.run {
            NetworkConfiguration.shared.speedDisplayUnit
        }
    }
    
    private func formatSpeed(_ bytesPerSecond: Double, unit: SpeedDisplayUnit) -> (value: String, unit: String) {
        // Reasonable sanity check
        guard bytesPerSecond < 1_000_000_000_000 else {
            return ("ERR", "?/s")
        }
        
        let formattedResult: (value: String, unit: String)
        
        switch unit {
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
