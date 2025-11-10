//
//  NetworkInterface.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import SwiftSnmpKit

struct NetworkInterface: Identifiable, Hashable, Sendable {
    let id: UUID
    let index: Int
    var name: String
    var description: String
    var ipAddress: String
    var subnetMask: String
    var macAddress: String
    var operStatus: String
    var speed: String
    var alias: String
    
    nonisolated init(index: Int, name: String, description: String, ipAddress: String = "N/A", subnetMask: String = "N/A", macAddress: String = "N/A", operStatus: String = "Unknown", speed: String = "N/A", alias: String = "") {
        self.id = UUID()
        self.index = index
        self.name = name
        self.description = description
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.macAddress = macAddress
        self.operStatus = operStatus
        self.speed = speed
        self.alias = alias
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(name)
    }
    
    static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        return lhs.index == rhs.index && lhs.name == rhs.name
    }
}

// MARK: - Network Interface Discovery

enum NetworkDiscoveryError: Error, LocalizedError {
    case snmpUnavailable
    case connectionTimeout
    case authenticationFailed
    case deviceUnreachable
    case interfaceNotFound
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .snmpUnavailable:
            return "SNMP service is not available"
        case .connectionTimeout:
            return "Connection timeout while discovering interfaces"
        case .authenticationFailed:
            return "SNMP authentication failed. Check your community string."
        case .deviceUnreachable:
            return "Device is unreachable. Check IP address and network connectivity."
        case .interfaceNotFound:
            return "No network interfaces found on the device"
        case .invalidResponse:
            return "Invalid response from SNMP device"
        }
    }
}

class NetworkInterfaceDiscovery {
    
    // SNMP OIDs for interface information
    private static let ifNameOID = "1.3.6.1.2.1.31.1.1.1.1"
    private static let ifDescrOID = "1.3.6.1.2.1.2.2.1.2"
    private static let ifOperStatusOID = "1.3.6.1.2.1.2.2.1.8"
    private static let ifHighSpeedOID = "1.3.6.1.2.1.31.1.1.1.15"
    private static let ifAliasOID = "1.3.6.1.2.1.31.1.1.1.18"
    
    static func discoverInterfaces(host: String, community: String) async throws -> [NetworkInterface] {
        print("DEBUG: Starting shell-based interface discovery for host: \(host)")
        
        // Use shell commands instead of SwiftSnmpKit
        async let ifNames = shellSnmpWalk(host: host, community: community, oid: ifNameOID)
        async let ifDescriptions = shellSnmpWalk(host: host, community: community, oid: ifDescrOID)
        async let ifStatuses = shellSnmpWalk(host: host, community: community, oid: ifOperStatusOID)
        async let ifSpeeds = shellSnmpWalk(host: host, community: community, oid: ifHighSpeedOID)
        async let ifAliases = shellSnmpWalk(host: host, community: community, oid: ifAliasOID)
        
        let (nameDict, descDict, statusDict, speedDict, aliasDict) = try await (ifNames, ifDescriptions, ifStatuses, ifSpeeds, ifAliases)
        
        print("DEBUG: Shell SNMP walks completed for \(host), processing results")
        
        guard !descDict.isEmpty else {
            print("DEBUG: No interfaces found in description table for \(host)")
            throw NetworkDiscoveryError.interfaceNotFound
        }
        
        var interfaces: [NetworkInterface] = []
        
        for (index, description) in descDict {
            let name = nameDict[index] ?? description
            let alias = aliasDict[index] ?? ""
            let statusValue = statusDict[index] ?? "1"
            let operStatus = formatOperStatus(Int(statusValue) ?? 1)
            let speedValue = speedDict[index]
            let speed = speedValue.flatMap(UInt.init).map { formatSpeed($0 * 1_000_000) } ?? "N/A"
            
            let interface = NetworkInterface(
                index: index,
                name: name,
                description: description,
                operStatus: operStatus,
                speed: speed,
                alias: alias
            )
            
            interfaces.append(interface)
        }
        
        // Filter out loopback and null interfaces
        let filteredInterfaces = interfaces.filter { interface in
            return !interface.name.isEmpty &&
                   !interface.name.hasPrefix("lo") &&
                   interface.name != "lo" &&
                   !interface.name.hasPrefix("null") &&
                   interface.name != "null" &&
                   !interface.name.contains("127.0.0.1") &&
                   !interface.description.contains("loopback")
        }
        
        print("DEBUG: Found \(filteredInterfaces.count) filtered interfaces for \(host)")
        return filteredInterfaces.sorted { $0.index < $1.index }
    }
    
    // Shell-based SNMP walk implementation
    private static func shellSnmpWalk(host: String, community: String, oid: String) async throws -> [Int: String] {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    print("DEBUG: Running snmpwalk for \(host) with OID \(oid)")
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oq", // Quiet output format
                        "-t", "10", // 10 second timeout
                        "-r", "2", // 2 retries
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    print("DEBUG: snmpwalk for \(host) returned status \(process.terminationStatus)")
                    
                    if process.terminationStatus == 0 {
                        var results: [Int: String] = [:]
                        
                        for line in output.components(separatedBy: .newlines) {
                            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedLine.isEmpty && !trimmedLine.contains("No Such Object") {
                                // Parse: "OID.index value"
                                let parts = trimmedLine.components(separatedBy: " ")
                                if parts.count >= 2 {
                                    let oidPart = parts[0]
                                    var value = parts[1...].joined(separator: " ")
                                    
                                    // Remove quotes if present
                                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                                    
                                    // Extract index from OID (last number after final dot)
                                    if let lastDot = oidPart.lastIndex(of: ".") {
                                        let indexStr = String(oidPart[oidPart.index(after: lastDot)...])
                                        if let index = Int(indexStr) {
                                            results[index] = value
                                        }
                                    }
                                }
                            }
                        }
                        
                        print("DEBUG: Parsed \(results.count) results from snmpwalk for \(host)")
                        continuation.resume(returning: results)
                    } else {
                        print("DEBUG: snmpwalk failed for \(host) with status \(process.terminationStatus)")
                        print("DEBUG: Output: \(output)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
                    print("DEBUG: snmpwalk exception for \(host): \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func formatOperStatus(_ status: Int) -> String {
        switch status {
        case 1: return "Up"
        case 2: return "Down"
        case 3: return "Testing"
        case 4: return "Unknown"
        case 5: return "Dormant"
        case 6: return "Not Present"
        case 7: return "Lower Layer Down"
        default: return "Unknown"
        }
    }
    
    private static func formatSpeed(_ bps: UInt) -> String {
        guard bps > 0 else { return "N/A" }
        let kbit = Double(bps) / 1_000
        let mbit = kbit / 1_000
        let gbit = mbit / 1_000
        
        if gbit >= 1 {
            return String(format: "%.1f Gbps", gbit)
        } else if mbit >= 1 {
            return String(format: "%.0f Mbps", mbit)
        } else if kbit >= 1 {
            return String(format: "%.0f Kbps", kbit)
        } else {
            return "\(bps) bps"
        }
    }
}