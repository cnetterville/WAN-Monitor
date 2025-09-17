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
    private var _consecutiveFailures = 0
    private let maxConsecutiveFailures = 5
    
    // SNMP OIDs - try 64-bit counters for high speed interfaces
    private let ifHCInOctetsOID = "1.3.6.1.2.1.31.1.1.1.6"   // 64-bit counter
    private let ifHCOutOctetsOID = "1.3.6.1.2.1.31.1.1.1.10" // 64-bit counter
    // Fallback to 32-bit if needed: 1.3.6.1.2.1.2.2.1.10 and 1.3.6.1.2.1.2.2.1.16
    
    // Smoothing
    private var _smoothedUploadSpeed: Double = 0.0
    private var _smoothedDownloadSpeed: Double = 0.0
    private let smoothingFactor: Double = 0.9  // Increased from 0.7 to 0.9 for minimal smoothing
    
    // Thread-safe accessors
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
    
    private var consecutiveFailures: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _consecutiveFailures
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _consecutiveFailures = newValue
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
    
    // MARK: - SNMP Helper
    
    private func getSnmpSender() async throws -> SnmpSender {
        // First try getting the shared instance
        if let snmp = SnmpSender.shared {
            return snmp
        }
        
        // If shared is nil, wait and try again (maybe it's still initializing)
        for attempt in 1...5 {
            print("DEBUG: SNMP attempt \(attempt): SnmpSender.shared is nil, waiting...")
            try await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000)) // Exponential backoff
            
            if let snmp = SnmpSender.shared {
                print("DEBUG: SNMP initialized on attempt \(attempt)")
                return snmp
            }
        }
        
        print("ERROR: SnmpSender.shared is nil after all attempts")
        throw NetworkDiscoveryError.snmpUnavailable
    }
    
    func discoverInterfaces() async throws -> [NetworkInterface] {
        print("DEBUG: ===== Starting interface discovery =====")
        print("DEBUG: Device: \(label)")
        print("DEBUG: Host: \(host)")  
        print("DEBUG: Community: \(community)")
        print("DEBUG: ==========================================")
        
        // Use shell snmpwalk instead of SwiftSnmpKit
        let result = try await shellBasedInterfaceDiscovery()
        print("DEBUG: Interface discovery completed for \(label), found \(result.count) interfaces")
        
        // Log the first few interface names for verification
        for (i, interface) in result.prefix(5).enumerated() {
            print("DEBUG: Interface \(i+1): \(interface.name) (\(interface.description))")
        }
        
        return result
    }
    
    private func shellBasedInterfaceDiscovery() async throws -> [NetworkInterface] {
        // Get interface names using snmpwalk
        let ifNames = try await shellSnmpWalk(host: host, community: community, oid: "1.3.6.1.2.1.31.1.1.1.1")
        let ifDescr = try await shellSnmpWalk(host: host, community: community, oid: "1.3.6.1.2.1.2.2.1.2")
        let ifOperStatus = try await shellSnmpWalk(host: host, community: community, oid: "1.3.6.1.2.1.2.2.1.8")
        
        var interfaces: [NetworkInterface] = []
        
        // Create a set of all interface indices we've seen
        var allIndices = Set<Int>()
        allIndices.formUnion(ifNames.keys)
        allIndices.formUnion(ifDescr.keys)
        allIndices.formUnion(ifOperStatus.keys)
        
        print("DEBUG: Found interface indices: \(Array(allIndices).sorted())")
        
        for index in allIndices {
            let name = ifNames[index] ?? "Interface\(index)"
            let description = ifDescr[index] ?? name
            let operStatusValue = ifOperStatus[index] ?? "down"  // Default to "down"
            
            // Handle both textual ("up"/"down") and numeric ("1"/"2") status values
            let status: String
            if operStatusValue.lowercased() == "up" || operStatusValue == "1" {
                status = "Up"
            } else if operStatusValue.lowercased() == "down" || operStatusValue == "2" {
                status = "Down" 
            } else {
                // Handle other SNMP status values
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
            
            print("DEBUG: Processing interface \(index): name='\(name)', desc='\(description)', status='\(status)' (raw: '\(operStatusValue)')")
            
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
                print("DEBUG: Added interface \(index): \(name) (\(description)) - \(status)")
            } else {
                print("DEBUG: Filtered out interface \(index): \(name) (reason: loopback=\(isLoopback), null=\(isNull), system=\(isSystemInterface))")
            }
        }
        
        // Sort interfaces: "Up" interfaces first, then by index
        let sortedInterfaces = interfaces.sorted { interface1, interface2 in
            if interface1.operStatus == "Up" && interface2.operStatus != "Up" {
                return true  // interface1 (Up) comes first
            }
            if interface1.operStatus != "Up" && interface2.operStatus == "Up" {
                return false // interface2 (Up) comes first
            }
            return interface1.index < interface2.index  // Same status, sort by index
        }
        
        print("DEBUG: Final interface list (\(sortedInterfaces.count) interfaces):")
        print("DEBUG: === UP INTERFACES ===")
        for interface in sortedInterfaces.filter({ $0.operStatus == "Up" }) {
            print("DEBUG: ✅ \(interface.index): \(interface.name) (\(interface.description))")
        }
        print("DEBUG: === DOWN/OTHER INTERFACES ===")
        for interface in sortedInterfaces.filter({ $0.operStatus != "Up" }) {
            print("DEBUG: ❌ \(interface.index): \(interface.name) (\(interface.description)) - \(interface.operStatus)")
        }
        
        return sortedInterfaces
    }
    
    private func shellSnmpWalk(host: String, community: String, oid: String) async throws -> [Int: String] {
        print("DEBUG: Starting snmpwalk for host=\(host), community=\(community), oid=\(oid)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oq", // Quiet output
                        "-t", "10", // 10 second timeout
                        host,
                        oid
                    ]
                    
                    print("DEBUG: Running command: snmpwalk -v2c -c \(community) -Oq -t 10 \(host) \(oid)")
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    print("DEBUG: snmpwalk exit status: \(process.terminationStatus)")
                    print("DEBUG: snmpwalk output (first 200 chars): \(String(output.prefix(200)))")
                    
                    if process.terminationStatus == 0 {
                        var results: [Int: String] = [:]
                        
                        for line in output.components(separatedBy: .newlines) {
                            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedLine.isEmpty {
                                let parts = trimmedLine.components(separatedBy: " ")
                                if parts.count >= 2 {
                                    let oidPart = parts[0]
                                    let value = parts[1...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                                    
                                    if let lastDot = oidPart.lastIndex(of: ".") {
                                        let indexStr = String(oidPart[oidPart.index(after: lastDot)...])
                                        if let index = Int(indexStr) {
                                            results[index] = value
                                            print("DEBUG: Parsed interface \(index): \(value)")
                                        }
                                    }
                                }
                            }
                        }
                        
                        print("DEBUG: Total parsed results: \(results.count)")
                        continuation.resume(returning: results)
                    } else {
                        print("DEBUG: snmpwalk failed with status \(process.terminationStatus), full output: \(output)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
                    print("DEBUG: snmpwalk exception: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updateTrafficData(availableInterfaces: [NetworkInterface]) async throws -> (upload: Double, download: Double, formattedUpload: (String, String), formattedDownload: (String, String)) {
        // Skip if too many consecutive failures to avoid issues
        guard consecutiveFailures < 3 else {
            print("DEBUG: \(label) - Skipping update due to consecutive failures (\(consecutiveFailures))")
            throw NetworkDiscoveryError.deviceUnreachable
        }
        
        print("DEBUG: \(label) - Starting traffic update - Interface count: \(availableInterfaces.count)")
        print("DEBUG: \(label) - Current interface index: \(interfaceIndex?.description ?? "nil")")
        print("DEBUG: \(label) - Looking for interface named: '\(interfaceName)'")
        
        // Ensure we have interface index
        if interfaceIndex == nil {
            if !interfaceName.isEmpty {
                if let interface = availableInterfaces.first(where: { $0.name == interfaceName }) {
                    interfaceIndex = interface.index
                    print("DEBUG: \(label) - Found interface '\(interfaceName)' at index \(interface.index)")
                } else {
                    print("DEBUG: \(label) - Interface '\(interfaceName)' not found in available interfaces")
                    print("DEBUG: \(label) - Available interfaces: \(availableInterfaces.map { $0.name }.joined(separator: ", "))")
                }
            }
            
            if interfaceIndex == nil {
                if let interface = availableInterfaces.first(where: { $0.operStatus == "Up" && $0.ipAddress != "N/A" }) {
                    interfaceIndex = interface.index
                    print("DEBUG: \(label) - Auto-selected first UP interface: \(interface.name) (index \(interface.index))")
                } else if let interface = availableInterfaces.first(where: { $0.operStatus == "Up" }) {
                    interfaceIndex = interface.index
                    print("DEBUG: \(label) - Auto-selected first UP interface (no IP check): \(interface.name) (index \(interface.index))")
                }
            }
            
            guard interfaceIndex != nil else {
                consecutiveFailures += 1
                print("DEBUG: \(label) - No suitable interface found, consecutive failures: \(consecutiveFailures)")
                throw NetworkDiscoveryError.interfaceNotFound
            }
        }
        
        let inOid = "\(ifHCInOctetsOID).\(interfaceIndex!)"
        let outOid = "\(ifHCOutOctetsOID).\(interfaceIndex!)"
        
        print("DEBUG: \(label) - Starting shell SNMP requests")
        
        do {
            // Use shell snmpget command instead of SwiftSnmpKit
            let currentInOctets = try await shellSnmpGet(host: host, community: community, oid: inOid)
            let currentOutOctets = try await shellSnmpGet(host: host, community: community, oid: outOid)
            
            let now = Date()
            
            // Calculate speeds if we have previous data
            if let lastIn = lastInOctets,
               let lastOut = lastOutOctets,
               let lastTime = lastTimestamp {
                
                let timeDiff = now.timeIntervalSince(lastTime)
                
                // Debug output
                print("DEBUG: \(label) - TimeDiff: \(timeDiff)s, CurrentIn: \(currentInOctets), LastIn: \(lastIn)")
                
                // Minimum time difference to avoid division by very small numbers
                guard timeDiff > 2.0 else {
                    print("DEBUG: \(label) - Time difference too small (\(timeDiff)s), skipping calculation")
                    return (smoothedUploadSpeed, smoothedDownloadSpeed, formatSpeed(smoothedUploadSpeed), formatSpeed(smoothedDownloadSpeed))
                }
                
                // Handle counter wraparound - but also validate reasonable values
                let inDiff: UInt64
                let outDiff: UInt64
                
                if currentInOctets >= lastIn {
                    inDiff = currentInOctets - lastIn
                } else {
                    // Counter wrapped - check if this is reasonable
                    let wrappedDiff = (UInt64.max - lastIn) + currentInOctets
                    if wrappedDiff > 1_000_000_000_000 { // More than 1TB in one interval seems wrong
                        print("DEBUG: \(label) - Counter wraparound seems unreasonable, resetting")
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
                        print("DEBUG: \(label) - Counter wraparound seems unreasonable, resetting")
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
                
                print("DEBUG: \(label) - Raw calculation details:")
                print("DEBUG: \(label) - InDiff: \(inDiff) bytes, OutDiff: \(outDiff) bytes, TimeDiff: \(timeDiff)s")
                print("DEBUG: \(label) - Calculated: Up=\(uploadBps) bytes/s (\(uploadBps * 8 / 1_000_000) Mbps), Down=\(downloadBps) bytes/s (\(downloadBps * 8 / 1_000_000) Mbps)")
                
                print("DEBUG: \(label) - Raw speeds: Up=\(uploadBps) bytes/s, Down=\(downloadBps) bytes/s")
                
                // Sanity check - if speeds are unreasonably high, reset
                if downloadBps > 10_000_000_000 || uploadBps > 10_000_000_000 {
                    print("DEBUG: \(label) - Calculated speeds seem unreasonable, resetting")
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
                
                // Reset error state on success
                consecutiveFailures = 0
                
                print("DEBUG: \(label) - Final speeds: Up=\(smoothedUploadSpeed) bytes/s, Down=\(smoothedDownloadSpeed) bytes/s")
                
                return (smoothedUploadSpeed, smoothedDownloadSpeed, formatSpeed(smoothedUploadSpeed), formatSpeed(smoothedDownloadSpeed))
            } else {
                // First run - just store values
                print("DEBUG: \(label) - First run, storing baseline: In=\(currentInOctets), Out=\(currentOutOctets)")
                lastInOctets = currentInOctets
                lastOutOctets = currentOutOctets
                lastTimestamp = now
                
                return (0.0, 0.0, ("-", "-"), ("-", "-"))
            }
            
        } catch {
            consecutiveFailures += 1
            print("DEBUG: \(label) - Shell SNMP error: \(error), consecutive failures: \(consecutiveFailures)")
            throw error
        }
    }
    
    func updateLatency() async -> (latency: Double?, formatted: String) {
        let host = pingHost.isEmpty ? "8.8.8.8" : pingHost
        
        do {
            // Use withTimeout for ping operations
            let result = try await withThrowingTaskGroup(of: (Double?, String).self) { group in
                group.addTask {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                    process.arguments = ["-c", "1", "-t", "5", host]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    try process.run()
                    process.waitUntilExit()
                    
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
                
                group.addTask {
                    try await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds timeout
                    throw NetworkDiscoveryError.connectionTimeout
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
        _consecutiveFailures = 0
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let config = NetworkConfiguration.shared
        
        // Reasonable sanity check - if values are too large, something is wrong
        guard bytesPerSecond < 1_000_000_000_000 else { // 1 TB/s max
            return ("ERR", "?/s")
        }
        
        let formattedResult: (value: String, unit: String)
        
        switch config.speedDisplayUnit {
        case .bits:
            // Convert bytes to bits per second
            let bitsPerSecond = bytesPerSecond * 8
            
            // Debug logging for auto-scaling
            print("DEBUG: formatSpeed (bits) - input: \(bytesPerSecond) B/s, converted: \(bitsPerSecond) bps")
            
            if bitsPerSecond < 1_000 {
                formattedResult = (String(format: "%.0f", bitsPerSecond), "bps")
                print("DEBUG: formatSpeed - using bps: \(formattedResult.value) \(formattedResult.unit)")
            } else if bitsPerSecond < 1_000_000 {
                let kbps = bitsPerSecond / 1_000
                formattedResult = (String(format: "%.1f", kbps), "Kbps")
                print("DEBUG: formatSpeed - using Kbps: \(kbps) -> \(formattedResult.value) \(formattedResult.unit)")
            } else if bitsPerSecond < 1_000_000_000 {
                let mbps = bitsPerSecond / 1_000_000
                formattedResult = (String(format: "%.1f", mbps), "Mbps")
                print("DEBUG: formatSpeed - using Mbps: \(mbps) -> \(formattedResult.value) \(formattedResult.unit)")
            } else {
                let gbps = bitsPerSecond / 1_000_000_000
                formattedResult = (String(format: "%.2f", gbps), "Gbps")
                print("DEBUG: formatSpeed - using Gbps: \(gbps) -> \(formattedResult.value) \(formattedResult.unit)")
            }
            
        case .bytes:
            // Keep as bytes per second
            print("DEBUG: formatSpeed (bytes) - input: \(bytesPerSecond) B/s")
            
            if bytesPerSecond < 1_000 {
                formattedResult = (String(format: "%.0f", bytesPerSecond), "B/s")
                print("DEBUG: formatSpeed - using B/s: \(formattedResult.value) \(formattedResult.unit)")
            } else if bytesPerSecond < 1_000_000 {
                let kbs = bytesPerSecond / 1_000
                formattedResult = (String(format: "%.1f", kbs), "KB/s")
                print("DEBUG: formatSpeed - using KB/s: \(kbs) -> \(formattedResult.value) \(formattedResult.unit)")
            } else if bytesPerSecond < 1_000_000_000 {
                let mbs = bytesPerSecond / 1_000_000
                formattedResult = (String(format: "%.1f", mbs), "MB/s")
                print("DEBUG: formatSpeed - using MB/s: \(mbs) -> \(formattedResult.value) \(formattedResult.unit)")
            } else {
                let gbs = bytesPerSecond / 1_000_000_000
                formattedResult = (String(format: "%.2f", gbs), "GB/s")
                print("DEBUG: formatSpeed - using GB/s: \(gbs) -> \(formattedResult.value) \(formattedResult.unit)")
            }
        }
        
        // Clean up the value string to remove any unwanted characters
        let cleanedValue = formattedResult.value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (cleanedValue, formattedResult.unit)
    }
    
    // Helper function for timeout protection
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NetworkDiscoveryError.connectionTimeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // Shell-based SNMP implementation to replace the problematic SwiftSnmpKit
    private func shellSnmpGet(host: String, community: String, oid: String) async throws -> UInt64 {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpget")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oqv", // Quiet output, value only
                        "-t", "5", // 5 second timeout
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if process.terminationStatus == 0 {
                        if let value = UInt64(output) {
                            continuation.resume(returning: value)
                        } else {
                            continuation.resume(throwing: NetworkDiscoveryError.invalidResponse)
                        }
                    } else {
                        print("DEBUG: snmpget failed with status \(process.terminationStatus), output: \(output)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}