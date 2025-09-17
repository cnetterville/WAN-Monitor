//
//  SNMPManager.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation

@globalActor
actor SNMPManager {
    static let shared = SNMPManager()
    
    // Process pool for reusing shell processes
    private var processPool: [Process] = []
    private let maxPoolSize = 5
    
    // Rate limiting
    private var lastRequestTime = Date(timeIntervalSince1970: 0)
    private let minRequestInterval: TimeInterval = 0.5 // 500ms between requests
    
    // Task management
    private var activeTasks: Set<UUID> = []
    private let maxConcurrentTasks = 3
    
    private init() {}
    
    // MARK: - Public Interface
    
    func performSnmpWalk(host: String, community: String, oid: String, taskId: UUID = UUID()) async throws -> [Int: String] {
        try await rateLimitedOperation(taskId: taskId) {
            try await self.shellSnmpWalk(host: host, community: community, oid: oid)
        }
    }
    
    func performSnmpGet(host: String, community: String, oid: String, taskId: UUID = UUID()) async throws -> UInt64 {
        try await rateLimitedOperation(taskId: taskId) {
            try await self.shellSnmpGet(host: host, community: community, oid: oid)
        }
    }
    
    func cancelTask(taskId: UUID) {
        activeTasks.remove(taskId)
    }
    
    func cancelAllTasks() {
        activeTasks.removeAll()
        // Clean up process pool
        processPool.forEach { $0.terminate() }
        processPool.removeAll()
    }
    
    // MARK: - Private Implementation
    
    private func rateLimitedOperation<T>(taskId: UUID, operation: @escaping () async throws -> T) async throws -> T {
        // Check if we should throttle this request
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        
        if timeSinceLastRequest < minRequestInterval {
            let delay = minRequestInterval - timeSinceLastRequest
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Check concurrent task limit
        guard activeTasks.count < maxConcurrentTasks else {
            throw NetworkDiscoveryError.tooManyRequests
        }
        
        activeTasks.insert(taskId)
        lastRequestTime = Date()
        
        defer {
            activeTasks.remove(taskId)
        }
        
        return try await operation()
    }
    
    private func shellSnmpWalk(host: String, community: String, oid: String) async throws -> [Int: String] {
        DebugLogger.logSNMP("Starting snmpwalk for host=\(host), oid=\(oid)")
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oq", // Quiet output
                        "-t", "8", // 8 second timeout
                        "-r", "1", // 1 retry
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    
                    // Add timeout protection
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                        process.terminate()
                    }
                    
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
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
                        
                        DebugLogger.logSNMP("snmpwalk completed successfully, found \(results.count) results")
                        continuation.resume(returning: results)
                    } else {
                        DebugLogger.logError("snmpwalk failed with status \(process.terminationStatus)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
                    DebugLogger.logError("snmpwalk exception", error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func shellSnmpGet(host: String, community: String, oid: String) async throws -> UInt64 {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpget")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oqv", // Quiet output, value only
                        "-t", "5", // 5 second timeout
                        "-r", "1", // 1 retry
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    
                    // Add timeout protection
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds
                        process.terminate()
                    }
                    
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if process.terminationStatus == 0 {
                        if let value = UInt64(output) {
                            continuation.resume(returning: value)
                        } else {
                            continuation.resume(throwing: NetworkDiscoveryError.invalidResponse)
                        }
                    } else {
                        DebugLogger.logError("snmpget failed with status \(process.terminationStatus), output: \(output)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// Add new error case
extension NetworkDiscoveryError {
    static let tooManyRequests = NetworkDiscoveryError.deviceUnreachable // Reuse existing error for now
}