//
//  HistoryManager.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import Combine

struct NetworkDataPoint: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let uploadSpeed: Double // bytes per second
    let downloadSpeed: Double // bytes per second
    let latency: Double? // milliseconds
    let packetLoss: Double? // percentage (0.0 - 100.0)
    
    init(uploadSpeed: Double, downloadSpeed: Double, latency: Double?, packetLoss: Double? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.latency = latency
        self.packetLoss = packetLoss
    }
}

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    // Published arrays for SwiftUI observation
    @Published var device1History: [NetworkDataPoint] = []
    @Published var device2History: [NetworkDataPoint] = []
    
    // Configuration - dynamically calculated based on user settings
    private var maxDataPoints: Int {
        let config = NetworkConfiguration.shared
        let updateInterval = config.updateInterval
        let retentionSeconds = config.historyRetentionMinutes * 60
        return max(60, Int(Double(retentionSeconds) / updateInterval)) // Minimum 60 points
    }
    
    private var persistenceEnabled: Bool {
        NetworkConfiguration.shared.historySaveOnQuit
    }
    
    private let persistenceURL: URL
    
    private let processingQueue = DispatchQueue(label: "com.wanmonitor.history", qos: .utility)
    
    private var cleanupTimer: Timer?
    
    private init() {
        // Setup persistence location
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("WAN Monitor", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        persistenceURL = appFolder.appendingPathComponent("history.json")
        
        // Load persisted data
        loadHistory()
        
        setupCleanupTimer()
    }
    
    // MARK: - Data Management
    
    func addDataPoint(device: Int, uploadSpeed: Double, downloadSpeed: Double, latency: Double?, packetLoss: Double? = nil) {
        let dataPoint = NetworkDataPoint(
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed,
            latency: latency,
            packetLoss: packetLoss
        )
        
        if device == 1 {
            device1History.append(dataPoint)
            if device1History.count > maxDataPoints + 100 {
                let trimCount = device1History.count - maxDataPoints
                device1History.removeFirst(trimCount)
            }
        } else {
            device2History.append(dataPoint)
            if device2History.count > maxDataPoints + 100 {
                let trimCount = device2History.count - maxDataPoints
                device2History.removeFirst(trimCount)
            }
        }
        
        if (device1History.count + device2History.count) % 20 == 0 {
            saveHistoryAsync()
        }
    }
    
    func clearHistory(device: Int? = nil) {
        if let device = device {
            if device == 1 {
                device1History.removeAll()
            } else {
                device2History.removeAll()
            }
        } else {
            device1History.removeAll()
            device2History.removeAll()
        }
        saveHistoryAsync()
    }
    
    // MARK: - Statistics
    
    func getStatistics(device: Int, filteredHistory: [NetworkDataPoint]? = nil) -> NetworkStatistics {
        let history = filteredHistory ?? (device == 1 ? device1History : device2History)
        
        guard !history.isEmpty else {
            return NetworkStatistics()
        }
        
        let uploadSpeeds = history.map { $0.uploadSpeed }
        let downloadSpeeds = history.map { $0.downloadSpeed }
        let latencies = history.compactMap { $0.latency }
        let packetLosses = history.compactMap { $0.packetLoss }
        
        return NetworkStatistics(
            avgUpload: uploadSpeeds.reduce(0, +) / Double(uploadSpeeds.count),
            maxUpload: uploadSpeeds.max() ?? 0,
            minUpload: uploadSpeeds.min() ?? 0,
            avgDownload: downloadSpeeds.reduce(0, +) / Double(downloadSpeeds.count),
            maxDownload: downloadSpeeds.max() ?? 0,
            minDownload: downloadSpeeds.min() ?? 0,
            avgLatency: latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
            maxLatency: latencies.max(),
            minLatency: latencies.min(),
            avgPacketLoss: packetLosses.isEmpty ? nil : packetLosses.reduce(0, +) / Double(packetLosses.count),
            maxPacketLoss: packetLosses.max(),
            minPacketLoss: packetLosses.min(),
            dataPointCount: history.count,
            timeSpan: history.last?.timestamp.timeIntervalSince(history.first?.timestamp ?? Date()) ?? 0
        )
    }
    
    // MARK: - Cleanup
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                await self?.performCleanup()
            }
        }
    }
    
    private func performCleanup() async {
        let maxPoints = maxDataPoints
        
        if device1History.count > maxPoints {
            let trimCount = device1History.count - maxPoints
            device1History.removeFirst(trimCount)
            DebugLogger.log("Cleaned up \(trimCount) old data points from Device 1 history", category: "HISTORY")
        }
        
        if device2History.count > maxPoints {
            let trimCount = device2History.count - maxPoints
            device2History.removeFirst(trimCount)
            DebugLogger.log("Cleaned up \(trimCount) old data points from Device 2 history", category: "HISTORY")
        }
    }
    
    // MARK: - Persistence
    
    nonisolated private func saveHistoryAsync() {
        Task { @MainActor in
            guard self.persistenceEnabled else { return }
            
            let device1Copy = self.device1History
            let device2Copy = self.device2History
            let url = self.persistenceURL
            
            // Encode on main actor
            let data = HistoryData(
                device1History: device1Copy,
                device2History: device2Copy
            )
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            guard let jsonData = try? encoder.encode(data) else {
                DebugLogger.logError("Failed to encode history data")
                return
            }
            
            // Write to disk on background thread
            Task.detached {
                do {
                    try jsonData.write(to: url, options: .atomic)
                } catch {
                    DebugLogger.logError("Failed to write history to disk", error: error)
                }
            }
        }
    }
    
    private func saveHistory() {
        guard persistenceEnabled else { return }
        
        let data = HistoryData(
            device1History: device1History,
            device2History: device2History
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: persistenceURL)
        } catch {
            DebugLogger.logError("Failed to save history", error: error)
        }
    }
    
    nonisolated private func loadHistory() {
        Task { @MainActor in
            let config = NetworkConfiguration.shared
            
            guard config.historyLoadOnStartup else {
                DebugLogger.logConfig("History loading disabled by user preference")
                return
            }
            
            let url = self.persistenceURL
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            
            let cutoffHours = config.historyRetentionHoursOnStartup
            
            // Read from disk on background thread
            Task.detached {
                guard let jsonData = try? Data(contentsOf: url) else {
                    DebugLogger.logError("Failed to read history file")
                    return
                }
                
                // Decode on main actor
                await MainActor.run {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let data = try decoder.decode(HistoryData.self, from: jsonData)
                        
                        // Trim old data based on user preference
                        let cutoffDate = Date().addingTimeInterval(-Double(cutoffHours) * 3600)
                        
                        let device1Filtered = data.device1History.filter { $0.timestamp >= cutoffDate }
                        let device2Filtered = data.device2History.filter { $0.timestamp >= cutoffDate }
                        
                        self.device1History = device1Filtered
                        self.device2History = device2Filtered
                        DebugLogger.logConfig("Loaded history (keeping last \(cutoffHours)h): Device 1: \(device1Filtered.count) points, Device 2: \(device2Filtered.count) points")
                    } catch {
                        DebugLogger.logError("Failed to decode history", error: error)
                    }
                }
            }
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
}

// MARK: - Supporting Types

struct HistoryData: Codable, @unchecked Sendable {
    let device1History: [NetworkDataPoint]
    let device2History: [NetworkDataPoint]
}

struct NetworkStatistics {
    let avgUpload: Double
    let maxUpload: Double
    let minUpload: Double
    let avgDownload: Double
    let maxDownload: Double
    let minDownload: Double
    let avgLatency: Double?
    let maxLatency: Double?
    let minLatency: Double?
    let avgPacketLoss: Double?
    let maxPacketLoss: Double?
    let minPacketLoss: Double?
    let dataPointCount: Int
    let timeSpan: TimeInterval
    
    init(avgUpload: Double = 0, maxUpload: Double = 0, minUpload: Double = 0,
         avgDownload: Double = 0, maxDownload: Double = 0, minDownload: Double = 0,
         avgLatency: Double? = nil, maxLatency: Double? = nil, minLatency: Double? = nil,
         avgPacketLoss: Double? = nil, maxPacketLoss: Double? = nil, minPacketLoss: Double? = nil,
         dataPointCount: Int = 0, timeSpan: TimeInterval = 0) {
        self.avgUpload = avgUpload
        self.maxUpload = maxUpload
        self.minUpload = minUpload
        self.avgDownload = avgDownload
        self.maxDownload = maxDownload
        self.minDownload = minDownload
        self.avgLatency = avgLatency
        self.maxLatency = maxLatency
        self.minLatency = minLatency
        self.avgPacketLoss = avgPacketLoss
        self.maxPacketLoss = maxPacketLoss
        self.minPacketLoss = minPacketLoss
        self.dataPointCount = dataPointCount
        self.timeSpan = timeSpan
    }
}
