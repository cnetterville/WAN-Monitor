//
//  HistoryManager.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import Combine

struct NetworkDataPoint: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let uploadSpeed: Double // bytes per second
    let downloadSpeed: Double // bytes per second
    let latency: Double? // milliseconds
    
    init(uploadSpeed: Double, downloadSpeed: Double, latency: Double?) {
        self.id = UUID()
        self.timestamp = Date()
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.latency = latency
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
    
    private init() {
        // Setup persistence location
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("WAN Monitor", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        persistenceURL = appFolder.appendingPathComponent("history.json")
        
        // Load persisted data
        loadHistory()
    }
    
    // MARK: - Data Management
    
    func addDataPoint(device: Int, uploadSpeed: Double, downloadSpeed: Double, latency: Double?) {
        let dataPoint = NetworkDataPoint(
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed,
            latency: latency
        )
        
        if device == 1 {
            device1History.append(dataPoint)
            // Trim to max size
            if device1History.count > maxDataPoints {
                device1History.removeFirst(device1History.count - maxDataPoints)
            }
        } else {
            device2History.append(dataPoint)
            // Trim to max size
            if device2History.count > maxDataPoints {
                device2History.removeFirst(device2History.count - maxDataPoints)
            }
        }
        
        // Periodically save (every 10 data points to reduce I/O)
        if (device1History.count + device2History.count) % 10 == 0 {
            saveHistory()
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
        saveHistory()
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
            dataPointCount: history.count,
            timeSpan: history.last?.timestamp.timeIntervalSince(history.first?.timestamp ?? Date()) ?? 0
        )
    }
    
    // MARK: - Persistence
    
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
    
    private func loadHistory() {
        let config = NetworkConfiguration.shared
        
        guard config.historyLoadOnStartup else {
            DebugLogger.logConfig("History loading disabled by user preference")
            return
        }
        
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        
        do {
            let jsonData = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try decoder.decode(HistoryData.self, from: jsonData)
            
            device1History = data.device1History
            device2History = data.device2History
            
            // Trim old data based on user preference
            let cutoffHours = config.historyRetentionHoursOnStartup
            let cutoffDate = Date().addingTimeInterval(-Double(cutoffHours) * 3600)
            device1History.removeAll { $0.timestamp < cutoffDate }
            device2History.removeAll { $0.timestamp < cutoffDate }
            
            DebugLogger.logConfig("Loaded history (keeping last \(cutoffHours)h): Device 1: \(device1History.count) points, Device 2: \(device2History.count) points")
        } catch {
            DebugLogger.logError("Failed to load history", error: error)
        }
    }
}

// MARK: - Supporting Types

struct HistoryData: Codable {
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
    let dataPointCount: Int
    let timeSpan: TimeInterval
    
    init(avgUpload: Double = 0, maxUpload: Double = 0, minUpload: Double = 0,
         avgDownload: Double = 0, maxDownload: Double = 0, minDownload: Double = 0,
         avgLatency: Double? = nil, maxLatency: Double? = nil, minLatency: Double? = nil,
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
        self.dataPointCount = dataPointCount
        self.timeSpan = timeSpan
    }
}