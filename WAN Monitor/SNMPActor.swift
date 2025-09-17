//
//  SNMPActor.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation

// Dedicated actor to manage all SNMP operations efficiently
actor SNMPActor {
    static let shared = SNMPActor()
    
    // Rate limiting
    private var lastRequestTime: Date = Date.distantPast
    private let minRequestInterval: TimeInterval = 0.5 // Minimum time between requests
    
    private init() {}
    
    func performSNMPWalk(host: String, community: String, oid: String) async throws -> [Int: String] {
        // Rate limiting
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minRequestInterval {
            try await Task.sleep(nanoseconds: UInt64((minRequestInterval - timeSinceLastRequest) * 1_000_000_000))
        }
        lastRequestTime = Date()
        
        return try await executeSnmpWalk(host: host, community: community, oid: oid)
    }
    
    func performSNMPGet(host: String, community: String, oid: String) async throws -> UInt64 {
        // Rate limiting
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minRequestInterval {
            try await Task.sleep(nanoseconds: UInt64((minRequestInterval - timeSinceLastRequest) * 1_000_000_000))
        }
        lastRequestTime = Date()
        
        return try await executeSnmpGet(host: host, community: community, oid: oid)
    }
    
    nonisolated private func executeSnmpWalk(host: String, community: String, oid: String) async throws -> [Int: String] {
        #if DEBUG
        print("DEBUG: Starting snmpwalk for host=\(host), community=\(community), oid=\(oid)")
        #endif
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
        process.arguments = [
            "-v2c",
            "-c", community,
            "-Oq", // Quiet output
            "-t", "5", // 5 second timeout (reduced from 10)
            host,
            oid
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
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
                                    }
                                }
                            }
                        }
                    }
                    
                    continuation.resume(returning: results)
                } else {
                    continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                }
            }
        }
    }
    
    nonisolated private func executeSnmpGet(host: String, community: String, oid: String) async throws -> UInt64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpget")
        process.arguments = [
            "-v2c",
            "-c", community,
            "-Oqv", // Quiet output, value only
            "-t", "3", // 3 second timeout (reduced from 5)
            host,
            oid
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
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
                    continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                }
            }
        }
    }
}
