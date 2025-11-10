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
    
    // Process management for better cleanup
    private var activeProcesses: [UUID: Process] = [:]
    private let maxActiveProcesses = 5
    
    private var processCreationTime: [UUID: Date] = [:]
    private let maxProcessLifetime: TimeInterval = 30.0
    
    // Rate limiting with adaptive behavior
    private var lastRequestTime = Date(timeIntervalSince1970: 0)
    private var minRequestInterval: TimeInterval = 0.05 // Reduced from 0.2 to 0.05 for faster response
    private var adaptiveDelay: TimeInterval = 0.0
    private let maxAdaptiveDelay: TimeInterval = 2.0 // Reduced from 5.0 to 2.0
    
    // Task management
    private var activeTasks: Set<UUID> = []
    private let maxConcurrentTasks = 3
    
    // Health tracking for adaptive behavior
    private var recentFailures = 0
    private var lastSuccessTime = Date()
    
    private init() {}
    
    // MARK: - Public Interface
    
    func performSnmpWalk(host: String, community: String, oid: String, updateInterval: TimeInterval = 2.0, taskId: UUID = UUID()) async throws -> [Int: String] {
        try await rateLimitedOperation(taskId: taskId, host: host, updateInterval: updateInterval) {
            try await self.shellSnmpWalk(host: host, community: community, oid: oid, taskId: taskId)
        }
    }
    
    func performSnmpGet(host: String, community: String, oid: String, updateInterval: TimeInterval = 2.0, taskId: UUID = UUID()) async throws -> UInt64 {
        try await rateLimitedOperation(taskId: taskId, host: host, updateInterval: updateInterval) {
            try await self.shellSnmpGet(host: host, community: community, oid: oid, taskId: taskId)
        }
    }
    
    func cancelTask(taskId: UUID) {
        activeTasks.remove(taskId)
        
        // Terminate associated process if exists
        if let process = activeProcesses[taskId] {
            if process.isRunning {
                process.terminate()
                DebugLogger.logNetwork("Terminated process for cancelled task \(taskId)")
            }
            activeProcesses.removeValue(forKey: taskId)
        }
    }
    
    func cancelAllTasks() {
        activeTasks.removeAll()
        
        // Terminate all active processes
        for (taskId, process) in activeProcesses {
            if process.isRunning {
                process.terminate()
                DebugLogger.logNetwork("Terminated process for task \(taskId)")
            }
        }
        activeProcesses.removeAll()
        processCreationTime.removeAll()
    }
    
    func cleanupStaleProcesses() {
        let now = Date()
        var staleTaskIds: [UUID] = []
        
        for (taskId, creationTime) in processCreationTime {
            if now.timeIntervalSince(creationTime) > maxProcessLifetime {
                staleTaskIds.append(taskId)
            }
        }
        
        for taskId in staleTaskIds {
            if let process = activeProcesses[taskId], process.isRunning {
                process.terminate()
                DebugLogger.logNetwork("Cleaned up stale process for task \(taskId)")
            }
            activeProcesses.removeValue(forKey: taskId)
            processCreationTime.removeValue(forKey: taskId)
        }
    }
    
    // MARK: - Private Implementation with Adaptive Behavior
    
    private func rateLimitedOperation<T>(taskId: UUID, host: String, updateInterval: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        // Minimal rate limiting - only prevent hammering
        let baseInterval = max(0.05, min(minRequestInterval, updateInterval * 0.1)) // Changed from 0.2 to 0.1 multiplier
        let currentInterval = baseInterval + adaptiveDelay
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        
        if timeSinceLastRequest < currentInterval {
            let delay = currentInterval - timeSinceLastRequest
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Check concurrent task limit
        guard activeTasks.count < maxConcurrentTasks else {
            throw NetworkDiscoveryError.tooManyRequests
        }
        
        // Check if we have too many active processes
        guard activeProcesses.count < maxActiveProcesses else {
            DebugLogger.logError("Too many active SNMP processes, rejecting request")
            throw NetworkDiscoveryError.tooManyRequests
        }
        
        activeTasks.insert(taskId)
        lastRequestTime = Date()
        
        defer {
            activeTasks.remove(taskId)
        }
        
        do {
            let result = try await operation()
            
            // Record success - reduce adaptive delay more aggressively
            recentFailures = max(0, recentFailures - 1)
            if recentFailures == 0 {
                adaptiveDelay = max(0, adaptiveDelay - 0.2) // Reduced from 0.1 to 0.2 for faster recovery
            }
            lastSuccessTime = Date()
            
            return result
            
        } catch {
            // Record failure - increase adaptive delay but less aggressively
            recentFailures += 1
            adaptiveDelay = min(maxAdaptiveDelay, adaptiveDelay + 0.1) // Reduced from 0.2 to 0.1
            
            DebugLogger.logError("SNMP operation failed for \(host), adaptive delay now: \(adaptiveDelay)s", error: error)
            throw error
        }
    }
    
    private func shellSnmpWalk(host: String, community: String, oid: String, taskId: UUID) async throws -> [Int: String] {
        DebugLogger.logSNMP("Starting snmpwalk for host=\(host), oid=\(oid), taskId=\(taskId)")
        
        // Capture adaptive timeout before entering Task.detached
        let adaptiveTimeout = min(15, max(5, 8 + Int(adaptiveDelay)))
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
                    
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oq", // Quiet output
                        "-t", "\(adaptiveTimeout)", // Use captured timeout
                        "-r", "1", // Single retry
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    // Register process for cleanup
                    await self.registerProcess(process, for: taskId)
                    
                    try process.run()
                    
                    // Add timeout protection with cleanup
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: UInt64((adaptiveTimeout + 2) * 1_000_000_000))
                        if process.isRunning {
                            process.terminate()
                            DebugLogger.logNetwork("Process timeout for task \(taskId)")
                        }
                    }
                    
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
                    // Cleanup process registration
                    await self.unregisterProcess(for: taskId)
                    
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
                    // Ensure cleanup on error
                    await self.unregisterProcess(for: taskId)
                    DebugLogger.logError("snmpwalk exception", error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func shellSnmpGet(host: String, community: String, oid: String, taskId: UUID) async throws -> UInt64 {
        // Capture adaptive timeout before entering Task.detached
        let adaptiveTimeout = min(10, max(3, 5 + Int(adaptiveDelay)))
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpget")
                    
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oqv", // Quiet output, value only
                        "-t", "\(adaptiveTimeout)", // Use captured timeout
                        "-r", "1", // Single retry
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    // Register process for cleanup
                    await self.registerProcess(process, for: taskId)
                    
                    try process.run()
                    
                    // Add timeout protection
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: UInt64((adaptiveTimeout + 1) * 1_000_000_000))
                        if process.isRunning {
                            process.terminate()
                            DebugLogger.logNetwork("Process timeout for task \(taskId)")
                        }
                    }
                    
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
                    // Cleanup process registration
                    await self.unregisterProcess(for: taskId)
                    
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
                    // Ensure cleanup on error
                    await self.unregisterProcess(for: taskId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Process Management
    
    private func registerProcess(_ process: Process, for taskId: UUID) {
        activeProcesses[taskId] = process
        processCreationTime[taskId] = Date()
        
        // Clean up stale processes opportunistically
        if activeProcesses.count > maxActiveProcesses - 1 {
            cleanupStaleProcesses()
        }
    }
    
    private func unregisterProcess(for taskId: UUID) {
        activeProcesses.removeValue(forKey: taskId)
        processCreationTime.removeValue(forKey: taskId)
    }
}

// MARK: - Enhanced Error Handling

extension NetworkDiscoveryError {
    static let tooManyRequests = NetworkDiscoveryError.deviceUnreachable
    
    var shouldRetry: Bool {
        switch self {
        case .connectionTimeout, .deviceUnreachable:
            return true
        case .authenticationFailed, .snmpUnavailable:
            return false
        case .interfaceNotFound, .invalidResponse:
            return true
        }
    }
    
    var retryDelay: TimeInterval {
        switch self {
        case .connectionTimeout:
            return 5.0
        case .deviceUnreachable:
            return 10.0
        case .interfaceNotFound:
            return 30.0
        default:
            return 5.0
        }
    }
}