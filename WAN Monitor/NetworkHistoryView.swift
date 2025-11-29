//
//  NetworkHistoryView.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import SwiftUI
import Charts

enum HistoryTimeRange: String, CaseIterable {
    case hour1 = "Last Hour"
    case hours6 = "Last 6 Hours"
    case hours24 = "Last 24 Hours"
    case days7 = "Last 7 Days"
    case days30 = "Last 30 Days"
    case all = "All Time"
    
    var timeInterval: TimeInterval? {
        switch self {
        case .hour1: return 3600
        case .hours6: return 3600 * 6
        case .hours24: return 3600 * 24
        case .days7: return 3600 * 24 * 7
        case .days30: return 3600 * 24 * 30
        case .all: return nil
        }
    }
    
    var maxDataPoints: Int {
        switch self {
        case .hour1: return 300      // ~12 seconds per point
        case .hours6: return 400     // ~54 seconds per point
        case .hours24: return 500    // ~2.8 minutes per point
        case .days7: return 600      // ~16.8 minutes per point
        case .days30: return 700     // ~1 hour per point
        case .all: return 800        // adaptive
        }
    }
}

struct NetworkHistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @ObservedObject var configuration = NetworkConfiguration.shared
    let deviceIndex: Int
    
    @State private var selectedTimeRange: HistoryTimeRange = .hours24
    @State private var processedData: ProcessedHistoryData?
    @State private var isProcessing = false
    @State private var lastProcessedCount: Int = 0
    @State private var processingTask: Task<Void, Never>?
    
    private var allHistory: [NetworkDataPoint] {
        if deviceIndex == 1 {
            return historyManager.device1History
        } else if deviceIndex == 2 {
            return historyManager.device2History
        } else {
            return historyManager.lanHistory
        }
    }
    
    private var deviceLabel: String {
        if deviceIndex == 1 {
            return configuration.device1Label
        } else if deviceIndex == 2 {
            return configuration.device2Label
        } else {
            return configuration.lanLabel
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if allHistory.isEmpty {
                    ContentUnavailableView(
                        "No History Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Start monitoring to collect network history")
                    )
                } else {
                    // Time Range Selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time Range")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Picker("Time Range", selection: $selectedTimeRange) {
                            ForEach(HistoryTimeRange.allCases, id: \.self) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedTimeRange) { _, _ in
                            processData()
                        }
                        
                        if let processed = processedData {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                                Text("Showing \(processed.sampledData.count) of \(processed.filteredCount) data points")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    if let processed = processedData {
                        // Statistics Cards
                        StatisticsCardsView(statistics: processed.statistics, deviceLabel: deviceLabel)
                        
                        // Upload Speed Chart
                        ChartCardView(title: "Upload Speed") {
                            UploadSpeedChart(data: processed.sampledData)
                        }
                        
                        // Download Speed Chart
                        ChartCardView(title: "Download Speed") {
                            DownloadSpeedChart(data: processed.sampledData)
                        }
                        
                        // Latency Chart
                        if processed.sampledData.contains(where: { $0.latency != nil }) {
                            ChartCardView(title: "Latency") {
                                LatencyChart(data: processed.sampledData, deviceIndex: deviceIndex)
                            }
                        }
                        
                        // Packet Loss Chart
                        if processed.sampledData.contains(where: { $0.packetLoss != nil }) {
                            ChartCardView(title: "Packet Loss") {
                                PacketLossChart(data: processed.sampledData)
                            }
                        }
                    } else if isProcessing {
                        ProgressView("Processing data...")
                            .frame(height: 200)
                    }
                    
                    // Clear History Button
                    Button(role: .destructive) {
                        historyManager.clearHistory(device: deviceIndex)
                        processedData = nil
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom)
                }
            }
            .padding()
        }
        .navigationTitle("\(deviceLabel) History")
        .task {
            processData()
        }
        .onChange(of: allHistory.count) { oldCount, newCount in
            // Cancel any pending processing task
            processingTask?.cancel()
            
            // Only reprocess when there's a significant change (every 50 points or 5% change)
            let threshold = max(50, Int(Double(lastProcessedCount) * 0.05))
            let countDiff = abs(newCount - lastProcessedCount)
            
            if countDiff >= threshold {
                // Debounce: wait a bit before processing to batch updates
                processingTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                    guard !Task.isCancelled else { return }
                    processData()
                }
            }
        }
    }
    
    private func processData() {
        // Cancel any existing processing
        processingTask?.cancel()
        
        isProcessing = true
        lastProcessedCount = allHistory.count
        
        processingTask = Task.detached(priority: .userInitiated) {
            let filtered = await filterHistory()
            let sampled = await sampleData(filtered, maxPoints: selectedTimeRange.maxDataPoints)
            let stats = await calculateStatistics(filtered)
            
            let processed = ProcessedHistoryData(
                sampledData: sampled,
                filteredCount: filtered.count,
                statistics: stats
            )
            
            await MainActor.run {
                self.processedData = processed
                self.isProcessing = false
            }
        }
    }
    
    private func filterHistory() async -> [NetworkDataPoint] {
        let history = allHistory
        
        guard let timeInterval = selectedTimeRange.timeInterval else {
            return history
        }
        
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        return history.filter { $0.timestamp >= cutoffDate }
    }
    
    private func sampleData(_ data: [NetworkDataPoint], maxPoints: Int) async -> [NetworkDataPoint] {
        guard data.count > maxPoints else { return data }
        
        // More stable sampling algorithm using time-based bucketing
        // This ensures consistent results even when data count changes slightly
        
        guard let firstTimestamp = data.first?.timestamp,
              let lastTimestamp = data.last?.timestamp else {
            return data
        }
        
        let timeRange = lastTimestamp.timeIntervalSince(firstTimestamp)
        let bucketDuration = timeRange / Double(maxPoints - 1)
        
        var sampled: [NetworkDataPoint] = []
        var currentBucketStart = firstTimestamp
        var dataIndex = 0
        
        // Always include first point
        sampled.append(data[0])
        
        // Create time-based buckets and select one point per bucket
        for bucketIndex in 1..<(maxPoints - 1) {
            currentBucketStart = firstTimestamp.addingTimeInterval(Double(bucketIndex) * bucketDuration)
            let nextBucketStart = currentBucketStart.addingTimeInterval(bucketDuration)
            
            // Find points in this bucket
            var bucketPoints: [NetworkDataPoint] = []
            while dataIndex < data.count {
                let point = data[dataIndex]
                if point.timestamp >= currentBucketStart && point.timestamp < nextBucketStart {
                    bucketPoints.append(point)
                    dataIndex += 1
                } else if point.timestamp >= nextBucketStart {
                    break
                } else {
                    dataIndex += 1
                }
            }
            
            // Use the middle point of the bucket (more stable than first/last)
            if !bucketPoints.isEmpty {
                let middleIndex = bucketPoints.count / 2
                sampled.append(bucketPoints[middleIndex])
            }
        }
        
        // Always include last point
        sampled.append(data.last!)
        
        return sampled
    }
    
    private func calculateStatistics(_ history: [NetworkDataPoint]) async -> NetworkStatistics {
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
}

// MARK: - Processed Data Cache

struct ProcessedHistoryData {
    let sampledData: [NetworkDataPoint]
    let filteredCount: Int
    let statistics: NetworkStatistics
}

// MARK: - Statistics Cards

struct StatisticsCardsView: View {
    let statistics: NetworkStatistics
    let deviceLabel: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatisticCard(
                    title: "Avg Upload",
                    value: formatSpeed(statistics.avgUpload),
                    icon: "arrow.up.circle.fill",
                    color: .red
                )
                
                StatisticCard(
                    title: "Max Upload",
                    value: formatSpeed(statistics.maxUpload),
                    icon: "arrow.up.circle",
                    color: .red
                )
            }
            
            HStack(spacing: 12) {
                StatisticCard(
                    title: "Avg Download",
                    value: formatSpeed(statistics.avgDownload),
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Max Download",
                    value: formatSpeed(statistics.maxDownload),
                    icon: "arrow.down.circle",
                    color: .blue
                )
            }
            
            if let avgLatency = statistics.avgLatency, let maxLatency = statistics.maxLatency {
                HStack(spacing: 12) {
                    StatisticCard(
                        title: "Avg Latency",
                        value: String(format: "%.1f ms", avgLatency),
                        icon: "timer",
                        color: .green
                    )
                    
                    StatisticCard(
                        title: "Max Latency",
                        value: String(format: "%.1f ms", maxLatency),
                        icon: "timer.circle",
                        color: .orange
                    )
                }
            }
            
            if let avgPacketLoss = statistics.avgPacketLoss, let maxPacketLoss = statistics.maxPacketLoss {
                HStack(spacing: 12) {
                    StatisticCard(
                        title: "Avg Packet Loss",
                        value: String(format: "%.1f%%", avgPacketLoss),
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                    
                    StatisticCard(
                        title: "Max Packet Loss",
                        value: String(format: "%.1f%%", maxPacketLoss),
                        icon: "exclamationmark.triangle",
                        color: .red
                    )
                }
            }
            
            HStack(spacing: 12) {
                StatisticCard(
                    title: "Data Points",
                    value: "\(statistics.dataPointCount)",
                    icon: "number.circle.fill",
                    color: .purple
                )
                
                StatisticCard(
                    title: "Time Span",
                    value: formatTimeSpan(statistics.timeSpan),
                    icon: "clock.fill",
                    color: .indigo
                )
            }
        }
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let config = NetworkConfiguration.shared
        let speedUnit = config.speedDisplayUnit
        
        switch speedUnit {
        case .bits:
            let bitsPerSecond = bytesPerSecond * 8
            if bitsPerSecond < 1_000 {
                return String(format: "%.0f bps", bitsPerSecond)
            } else if bitsPerSecond < 1_000_000 {
                return String(format: "%.1f Kbps", bitsPerSecond / 1_000)
            } else if bitsPerSecond < 1_000_000_000 {
                return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
            } else {
                return String(format: "%.2f Gbps", bitsPerSecond / 1_000_000_000)
            }
        case .bytes:
            if bytesPerSecond < 1_000 {
                return String(format: "%.0f B/s", bytesPerSecond)
            } else if bytesPerSecond < 1_000_000 {
                return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
            } else if bytesPerSecond < 1_000_000_000 {
                return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
            } else {
                return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000)
            }
        }
    }
    
    private func formatTimeSpan(_ timeInterval: TimeInterval) -> String {
        if timeInterval < 60 {
            return String(format: "%.0fs", timeInterval)
        } else if timeInterval < 3600 {
            return String(format: "%.0fm", timeInterval / 60)
        } else if timeInterval < 86400 {
            return String(format: "%.1fh", timeInterval / 3600)
        } else {
            return String(format: "%.1fd", timeInterval / 86400)
        }
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Chart Card Wrapper

struct ChartCardView<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            content
                .frame(height: 150)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Optimized Charts

struct UploadSpeedChart: View {
    let data: [NetworkDataPoint]
    
    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Speed", point.uploadSpeed * 8 / 1_000_000)
            )
            .foregroundStyle(.red.gradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Speed", point.uploadSpeed * 8 / 1_000_000)
            )
            .foregroundStyle(.red.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel("Mbps")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

struct DownloadSpeedChart: View {
    let data: [NetworkDataPoint]
    
    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Speed", point.downloadSpeed * 8 / 1_000_000)
            )
            .foregroundStyle(.blue.gradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Speed", point.downloadSpeed * 8 / 1_000_000)
            )
            .foregroundStyle(.blue.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel("Mbps")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

struct LatencyChart: View {
    let data: [NetworkDataPoint]
    let deviceIndex: Int
    
    private var config: NetworkConfiguration {
        NetworkConfiguration.shared
    }
    
    private var latencyData: [NetworkDataPoint] {
        data.filter { $0.latency != nil }
    }
    
    var body: some View {
        Chart(latencyData) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Latency", point.latency ?? 0)
            )
            .foregroundStyle(.green.gradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Latency", point.latency ?? 0)
            )
            .foregroundStyle(.green.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel("ms")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

struct PacketLossChart: View {
    let data: [NetworkDataPoint]
    
    private var packetLossData: [NetworkDataPoint] {
        data.filter { $0.packetLoss != nil }
    }
    
    var body: some View {
        Chart(packetLossData) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Packet Loss", point.packetLoss ?? 0)
            )
            .foregroundStyle(.orange.gradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Packet Loss", point.packetLoss ?? 0)
            )
            .foregroundStyle(.orange.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel("%")
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

#Preview {
    NavigationStack {
        NetworkHistoryView(deviceIndex: 1)
    }
}
