//
//  NetworkHistoryView.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import SwiftUI
import Charts

struct NetworkHistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @ObservedObject var configuration = NetworkConfiguration.shared
    let deviceIndex: Int
    
    private var history: [NetworkDataPoint] {
        deviceIndex == 1 ? historyManager.device1History : historyManager.device2History
    }
    
    private var statistics: NetworkStatistics {
        historyManager.getStatistics(device: deviceIndex)
    }
    
    private var deviceLabel: String {
        deviceIndex == 1 ? configuration.device1Label : configuration.device2Label
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if history.isEmpty {
                    ContentUnavailableView(
                        "No History Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Start monitoring to collect network history")
                    )
                } else {
                    // Statistics Cards
                    StatisticsCardsView(statistics: statistics, deviceLabel: deviceLabel)
                    
                    // Upload Speed Chart
                    ChartCardView(title: "Upload Speed") {
                        UploadSpeedChart(history: history)
                    }
                    
                    // Download Speed Chart
                    ChartCardView(title: "Download Speed") {
                        DownloadSpeedChart(history: history)
                    }
                    
                    // Latency Chart
                    if history.contains(where: { $0.latency != nil }) {
                        ChartCardView(title: "Latency") {
                            LatencyChart(history: history, deviceIndex: deviceIndex)
                        }
                    }
                    
                    // Clear History Button
                    Button(role: .destructive) {
                        historyManager.clearHistory(device: deviceIndex)
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
    }
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
        } else {
            return String(format: "%.1fh", timeInterval / 3600)
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

// MARK: - Individual Charts

struct UploadSpeedChart: View {
    let history: [NetworkDataPoint]
    
    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Speed", point.uploadSpeed * 8 / 1_000_000) // Convert to Mbps
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Speed", point.uploadSpeed * 8 / 1_000_000)
                )
                .foregroundStyle(.red.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel("Mbps")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

struct DownloadSpeedChart: View {
    let history: [NetworkDataPoint]
    
    var body: some View {
        Chart {
            ForEach(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Speed", point.downloadSpeed * 8 / 1_000_000) // Convert to Mbps
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Speed", point.downloadSpeed * 8 / 1_000_000)
                )
                .foregroundStyle(.blue.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel("Mbps")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

struct LatencyChart: View {
    let history: [NetworkDataPoint]
    let deviceIndex: Int
    
    private var config: NetworkConfiguration {
        NetworkConfiguration.shared
    }
    
    var body: some View {
        Chart {
            ForEach(history.filter { $0.latency != nil }) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Latency", point.latency ?? 0)
                )
                .foregroundStyle(latencyColor(point.latency ?? 0))
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Latency", point.latency ?? 0)
                )
                .foregroundStyle(latencyColor(point.latency ?? 0).opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel("ms")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
    
    private func latencyColor(_ latency: Double) -> Color {
        config.getLatencyColorSwiftUI(for: deviceIndex, latency: latency) ?? .green
    }
}

#Preview {
    NavigationStack {
        NetworkHistoryView(deviceIndex: 1)
    }
}