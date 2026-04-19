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
    
    // Process management
    private var activeProcesses: [UUID: Process] = [:]
    private let maxActiveProcesses = 5
    private var processCreationTime: [UUID: Date] = [:]
    private let maxProcessLifetime: TimeInterval = 30.0
    
    // Rate limiting with adaptive behavior
    private var lastRequestTime = Date(timeIntervalSince1970: 0)
    private var minRequestInterval: TimeInterval = 0.03
    private var adaptiveDelay: TimeInterval = 0.0
    private let maxAdaptiveDelay: TimeInterval = 1.5
    
    // Task management
    private var activeTasks: Set<UUID> = []
    private let maxConcurrentTasks = 5
    
    // Health tracking
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
    
    func performSnmpGetString(host: String, community: String, oid: String, updateInterval: TimeInterval = 2.0, taskId: UUID = UUID()) async throws -> String {
        try await rateLimitedOperation(taskId: taskId, host: host, updateInterval: updateInterval) {
            try await self.shellSnmpGetString(host: host, community: community, oid: oid, taskId: taskId)
        }
    }
    
    func cancelTask(taskId: UUID) {
        activeTasks.remove(taskId)
        if let process = activeProcesses[taskId] {
            if process.isRunning { process.terminate() }
            activeProcesses.removeValue(forKey: taskId)
        }
    }
    
    func cancelAllTasks() {
        activeTasks.removeAll()
        for (_, process) in activeProcesses where process.isRunning {
            process.terminate()
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
            }
            activeProcesses.removeValue(forKey: taskId)
            processCreationTime.removeValue(forKey: taskId)
        }
    }
    
    // MARK: - Rate Limiting
    
    private func rateLimitedOperation<T>(taskId: UUID, host: String, updateInterval: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        let baseInterval = max(0.03, min(minRequestInterval, updateInterval * 0.05))
        let currentInterval = baseInterval + adaptiveDelay
        let now = Date()
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        
        if timeSinceLastRequest < currentInterval {
            let delay = currentInterval - timeSinceLastRequest
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        guard activeTasks.count < maxConcurrentTasks else {
            throw NetworkDiscoveryError.tooManyRequests
        }
        guard activeProcesses.count < maxActiveProcesses else {
            DebugLogger.logError("Too many active SNMP processes, rejecting request")
            throw NetworkDiscoveryError.tooManyRequests
        }
        
        activeTasks.insert(taskId)
        lastRequestTime = Date()
        
        defer { activeTasks.remove(taskId) }
        
        do {
            let result = try await operation()
            recentFailures = max(0, recentFailures - 1)
            if recentFailures == 0 { adaptiveDelay = max(0, adaptiveDelay - 0.3) }
            lastSuccessTime = Date()
            return result
        } catch {
            recentFailures += 1
            adaptiveDelay = min(maxAdaptiveDelay, adaptiveDelay + 0.05)
            DebugLogger.logError("SNMP operation failed for \(host), adaptive delay now: \(adaptiveDelay)s", error: error)
            throw error
        }
    }
    
    // MARK: - Shell Implementations (reduced timeouts)
    
    private func shellSnmpWalk(host: String, community: String, oid: String, taskId: UUID) async throws -> [Int: String] {
        DebugLogger.logSNMP("Starting snmpwalk for host=\(host), oid=\(oid), taskId=\(taskId)")
        // Reduced: min 4s, max 8s (was min 6s, max 12s)
        let adaptiveTimeout = min(8, max(4, 4 + Int(adaptiveDelay)))
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpwalk")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oq",
                        "-t", "\(adaptiveTimeout)",
                        "-r", "1",
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    await self.registerProcess(process, for: taskId)
                    try process.run()
                    
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: UInt64((adaptiveTimeout + 2) * 1_000_000_000))
                        if process.isRunning { process.terminate() }
                    }
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    await self.unregisterProcess(for: taskId)
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if process.terminationStatus == 0 {
                        var results: [Int: String] = [:]
                        for line in output.components(separatedBy: .newlines) {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }
                            let parts = trimmed.components(separatedBy: " ")
                            guard parts.count >= 2 else { continue }
                            let value = parts[1...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                            if let lastDot = parts[0].lastIndex(of: "."),
                               let index = Int(String(parts[0][parts[0].index(after: lastDot)...])) {
                                results[index] = value
                            }
                        }
                        DebugLogger.logSNMP("snmpwalk completed, found \(results.count) results")
                        continuation.resume(returning: results)
                    } else {
                        DebugLogger.logError("snmpwalk failed with status \(process.terminationStatus)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
                    await self.unregisterProcess(for: taskId)
                    DebugLogger.logError("snmpwalk exception", error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func shellSnmpGet(host: String, community: String, oid: String, taskId: UUID) async throws -> UInt64 {
        // Reduced: min 2s, max 4s (was min 2s, max 8s)
        let adaptiveTimeout = min(4, max(2, 2 + Int(adaptiveDelay)))
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpget")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oqv",
                        "-t", "\(adaptiveTimeout)",
                        "-r", "1",
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    await self.registerProcess(process, for: taskId)
                    try process.run()
                    
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: UInt64((adaptiveTimeout + 1) * 1_000_000_000))
                        if process.isRunning { process.terminate() }
                    }
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    await self.unregisterProcess(for: taskId)
                    
                    let output = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
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
                    await self.unregisterProcess(for: taskId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func shellSnmpGetString(host: String, community: String, oid: String, taskId: UUID) async throws -> String {
        // Reduced: min 2s, max 4s (was min 2s, max 8s)
        let adaptiveTimeout = min(4, max(2, 2 + Int(adaptiveDelay)))
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .utility) {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/snmpget")
                    process.arguments = [
                        "-v2c",
                        "-c", community,
                        "-Oqv",
                        "-t", "\(adaptiveTimeout)",
                        "-r", "1",
                        host,
                        oid
                    ]
                    
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    await self.registerProcess(process, for: taskId)
                    try process.run()
                    
                    let timeoutTask = Task {
                        try await Task.sleep(nanoseconds: UInt64((adaptiveTimeout + 1) * 1_000_000_000))
                        if process.isRunning { process.terminate() }
                    }
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    await self.unregisterProcess(for: taskId)
                    
                    let output = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if process.terminationStatus == 0 && !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        DebugLogger.logError("snmpget (string) failed with status \(process.terminationStatus)")
                        continuation.resume(throwing: NetworkDiscoveryError.connectionTimeout)
                    }
                } catch {
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
        if activeProcesses.count > maxActiveProcesses - 1 {
            cleanupStaleProcesses()
        }
    }
    
    private func unregisterProcess(for taskId: UUID) {
        activeProcesses.removeValue(forKey: taskId)
        processCreationTime.removeValue(forKey: taskId)
    }
}

// MARK: - Error Helpers

extension NetworkDiscoveryError {
    static let tooManyRequests = NetworkDiscoveryError.deviceUnreachable
    
    var shouldRetry: Bool {
        switch self {
        case .connectionTimeout, .deviceUnreachable: return true
        case .authenticationFailed, .snmpUnavailable: return false
        case .interfaceNotFound, .invalidResponse:   return true
        }
    }
    
    var retryDelay: TimeInterval {
        switch self {
        case .connectionTimeout:  return 5.0
        case .deviceUnreachable:  return 10.0
        case .interfaceNotFound:  return 30.0
        default:                  return 5.0
        }
    }
}
