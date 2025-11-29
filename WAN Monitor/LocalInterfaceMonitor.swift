//
//  LocalInterfaceMonitor.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import SystemConfiguration
import Network

// MARK: - Local Interface Data

struct LocalInterfaceData: Sendable {
    let interfaceName: String
    var uploadSpeed: Double = 0.0
    var downloadSpeed: Double = 0.0
    var formattedUploadSpeed: (value: String, unit: String) = ("-", "-")
    var formattedDownloadSpeed: (value: String, unit: String) = ("-", "-")
    var lastInBytes: UInt64?
    var lastOutBytes: UInt64?
    var lastTimestamp: Date?
    
    init(interfaceName: String) {
        self.interfaceName = interfaceName
    }
}

struct LocalInterface: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let displayName: String
    let isActive: Bool
    let ipAddress: String?
    
    init(name: String, displayName: String, isActive: Bool, ipAddress: String? = nil) {
        self.id = UUID()
        self.name = name
        self.displayName = displayName
        self.isActive = isActive
        self.ipAddress = ipAddress
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: LocalInterface, rhs: LocalInterface) -> Bool {
        return lhs.name == rhs.name
    }
}

// MARK: - Local Interface Monitor State Actor

private actor LocalMonitorState {
    var smoothedUploadSpeed: Double = 0.0
    var smoothedDownloadSpeed: Double = 0.0
    var lastInBytes: UInt64?
    var lastOutBytes: UInt64?
    var lastTimestamp: Date?
    
    func getTrafficState() -> (lastIn: UInt64?, lastOut: UInt64?, lastTime: Date?, smoothedUp: Double, smoothedDown: Double) {
        return (lastInBytes, lastOutBytes, lastTimestamp, smoothedUploadSpeed, smoothedDownloadSpeed)
    }
    
    func updateTrafficState(inBytes: UInt64, outBytes: UInt64, timestamp: Date, smoothedUp: Double, smoothedDown: Double) {
        lastInBytes = inBytes
        lastOutBytes = outBytes
        lastTimestamp = timestamp
        smoothedUploadSpeed = smoothedUp
        smoothedDownloadSpeed = smoothedDown
    }
    
    func resetTrafficState() {
        lastInBytes = nil
        lastOutBytes = nil
        lastTimestamp = nil
        smoothedUploadSpeed = 0.0
        smoothedDownloadSpeed = 0.0
    }
    
    func resetAll() {
        resetTrafficState()
    }
}

// MARK: - Local Interface Monitor

final class LocalInterfaceMonitor: Sendable {
    let interfaceName: String
    let label: String
    
    private let state: LocalMonitorState
    private let smoothingFactor: Double = 0.7  // Reduced from 0.9 for more responsive updates
    
    init(interfaceName: String, label: String) {
        self.interfaceName = interfaceName
        self.label = label
        self.state = LocalMonitorState()
    }
    
    // MARK: - Interface Discovery
    
    static func discoverLocalInterfaces() -> [LocalInterface] {
        var interfaces: [LocalInterface] = []
        
        // Get network interfaces using BSD sockets API
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            DebugLogger.logError("Failed to get network interfaces")
            return []
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var interfaceMap: [String: (isActive: Bool, ipAddress: String?)] = [:]
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // Skip loopback and inactive interfaces
            guard !name.hasPrefix("lo"),
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"),
                  !name.hasPrefix("bridge") else {
                continue
            }
            
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isActive = isUp && isRunning
            
            // Try to extract IP address for IPv4
            var ipAddress: String?
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                             &hostname, socklen_t(hostname.count),
                             nil, 0, NI_NUMERICHOST) == 0 {
                    ipAddress = String(cString: hostname)
                }
            }
            
            // Update or add to map (prefer entries with IP addresses)
            if let existing = interfaceMap[name] {
                if ipAddress != nil && existing.ipAddress == nil {
                    interfaceMap[name] = (isActive: isActive || existing.isActive, ipAddress: ipAddress)
                } else if existing.ipAddress == nil {
                    interfaceMap[name] = (isActive: isActive || existing.isActive, ipAddress: nil)
                }
            } else {
                interfaceMap[name] = (isActive: isActive, ipAddress: ipAddress)
            }
        }
        
        // Convert to LocalInterface objects
        for (name, info) in interfaceMap {
            let displayName = getInterfaceDisplayName(name)
            let interface = LocalInterface(
                name: name,
                displayName: displayName,
                isActive: info.isActive,
                ipAddress: info.ipAddress
            )
            interfaces.append(interface)
        }
        
        // Sort: active interfaces first, then by name
        return interfaces.sorted { interface1, interface2 in
            if interface1.isActive != interface2.isActive {
                return interface1.isActive
            }
            return interface1.name < interface2.name
        }
    }
    
    private static func getInterfaceDisplayName(_ name: String) -> String {
        // Map common interface names to friendly names
        if name.hasPrefix("en0") { return "Ethernet/Wi-Fi (en0)" }
        if name.hasPrefix("en") { return "Network (\(name))" }
        if name.hasPrefix("pdp_ip") { return "Cellular (\(name))" }
        if name.hasPrefix("bridge") { return "Bridge (\(name))" }
        if name == "bond0" { return "Link Aggregation (bond0)" }
        return name
    }
    
    // MARK: - Traffic Monitoring
    
    func updateTrafficData() async throws -> (upload: Double, download: Double, formattedUpload: (String, String), formattedDownload: (String, String)) {
        
        DebugLogger.logSNMP("LAN (\(label)) - Starting traffic update for interface: \(interfaceName)")
        
        // Parse interface names - support comma-separated list for bonded connections
        let interfaceNames = interfaceName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Get current interface statistics - sum across all interfaces
        var totalInBytes: UInt64 = 0
        var totalOutBytes: UInt64 = 0
        var foundAnyInterface = false
        
        for ifName in interfaceNames {
            if let (inBytes, outBytes) = getInterfaceStats(interfaceName: ifName) {
                totalInBytes += inBytes
                totalOutBytes += outBytes
                foundAnyInterface = true
                DebugLogger.logSNMP("LAN (\(label)) - Interface \(ifName): in=\(inBytes), out=\(outBytes)")
            } else {
                DebugLogger.logError("LAN (\(label)) - Failed to get interface stats for \(ifName)")
            }
        }
        
        guard foundAnyInterface else {
            DebugLogger.logError("LAN (\(label)) - Failed to get stats for any interface in: \(interfaceName)")
            throw NetworkDiscoveryError.interfaceNotFound
        }
        
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
                DebugLogger.logSNMP("LAN (\(label)) - Time difference too small (\(timeDiff)s), using previous values")
                // Don't return "---", use the last known good values instead
                return (smoothedUp, smoothedDown, formatSpeed(smoothedUp, unit: speedDisplayUnit), formatSpeed(smoothedDown, unit: speedDisplayUnit))
            }
            
            // Handle counter wraparound with validation
            let inDiff: UInt64
            let outDiff: UInt64
            
            if totalInBytes >= lastIn {
                inDiff = totalInBytes - lastIn
            } else {
                // Counter wrapped around - this can happen on interface reset or system sleep/wake
                let wrappedDiff = (UInt64.max - lastIn) + totalInBytes
                if wrappedDiff > 1_000_000_000_000 {
                    // Unreasonable wraparound - likely interface reset, just update baseline
                    DebugLogger.logError("LAN (\(label)) - Unreasonable counter change detected, updating baseline")
                    await state.updateTrafficState(inBytes: totalInBytes, outBytes: totalOutBytes, timestamp: now, smoothedUp: smoothedUp, smoothedDown: smoothedDown)
                    // Keep showing last good values instead of "---"
                    return (smoothedUp, smoothedDown, formatSpeed(smoothedUp, unit: speedDisplayUnit), formatSpeed(smoothedDown, unit: speedDisplayUnit))
                }
                inDiff = wrappedDiff
            }
            
            if totalOutBytes >= lastOut {
                outDiff = totalOutBytes - lastOut
            } else {
                // Counter wrapped around
                let wrappedDiff = (UInt64.max - lastOut) + totalOutBytes
                if wrappedDiff > 1_000_000_000_000 {
                    DebugLogger.logError("LAN (\(label)) - Unreasonable counter change detected, updating baseline")
                    await state.updateTrafficState(inBytes: totalInBytes, outBytes: totalOutBytes, timestamp: now, smoothedUp: smoothedUp, smoothedDown: smoothedDown)
                    // Keep showing last good values instead of "---"
                    return (smoothedUp, smoothedDown, formatSpeed(smoothedUp, unit: speedDisplayUnit), formatSpeed(smoothedDown, unit: speedDisplayUnit))
                }
                outDiff = wrappedDiff
            }
            
            // Calculate bytes per second
            let downloadBps = Double(inDiff) / timeDiff
            let uploadBps = Double(outDiff) / timeDiff
            
            DebugLogger.logSNMP("LAN (\(label)) - Calculated: Up=\(uploadBps) bytes/s, Down=\(downloadBps) bytes/s (Combined from \(interfaceNames.count) interface(s))")
            
            // Sanity check - if speeds are unreasonably high (>100 Gbps), update baseline but keep showing data
            if downloadBps > 100_000_000_000 || uploadBps > 100_000_000_000 {
                DebugLogger.logError("LAN (\(label)) - Calculated speeds seem unreasonable (likely counter reset), updating baseline")
                await state.updateTrafficState(inBytes: totalInBytes, outBytes: totalOutBytes, timestamp: now, smoothedUp: smoothedUp, smoothedDown: smoothedDown)
                // Keep showing last good values instead of resetting to "---"
                return (smoothedUp, smoothedDown, formatSpeed(smoothedUp, unit: speedDisplayUnit), formatSpeed(smoothedDown, unit: speedDisplayUnit))
            }
            
            // Apply smoothing
            let newSmoothedUpload: Double
            let newSmoothedDownload: Double
            
            if smoothedUp == 0.0 && smoothedDown == 0.0 {
                newSmoothedUpload = uploadBps
                newSmoothedDownload = downloadBps
            } else {
                newSmoothedUpload = (smoothingFactor * uploadBps) + ((1 - smoothingFactor) * smoothedUp)
                newSmoothedDownload = (smoothingFactor * downloadBps) + ((1 - smoothingFactor) * smoothedDown)
            }
            
            // Store current values for next calculation
            await state.updateTrafficState(inBytes: totalInBytes, outBytes: totalOutBytes, timestamp: now, smoothedUp: newSmoothedUpload, smoothedDown: newSmoothedDownload)
            
            return (newSmoothedUpload, newSmoothedDownload, formatSpeed(newSmoothedUpload, unit: speedDisplayUnit), formatSpeed(newSmoothedDownload, unit: speedDisplayUnit))
        } else {
            // First run - just store values and show zeros instead of "---"
            DebugLogger.logSNMP("LAN (\(label)) - First run, storing baseline for \(interfaceNames.count) interface(s)")
            await state.updateTrafficState(inBytes: totalInBytes, outBytes: totalOutBytes, timestamp: now, smoothedUp: 0.0, smoothedDown: 0.0)
            
            let speedDisplayUnit = await getSpeedDisplayUnit()
            return (0.0, 0.0, formatSpeed(0.0, unit: speedDisplayUnit), formatSpeed(0.0, unit: speedDisplayUnit))
        }
    }
    
    private func getInterfaceStats(interfaceName: String) -> (inBytes: UInt64, outBytes: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            if name == interfaceName, let data = interface.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self)
                let inBytes = UInt64(networkData.pointee.ifi_ibytes)
                let outBytes = UInt64(networkData.pointee.ifi_obytes)
                return (inBytes, outBytes)
            }
        }
        
        return nil
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
