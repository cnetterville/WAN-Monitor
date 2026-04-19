//
//  DashboardView.swift
//  WAN Monitor
//
//  A comprehensive dashboard for monitoring all network connections
//

import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var monitor: ConnectionMonitor
    @ObservedObject var configuration = NetworkConfiguration.shared
    @State private var selectedDevice: Int = 1
    @State private var selectedTimeRange: DashboardTimeRange = .minutes10
    @State private var showingAlerts = false
    
    enum DashboardTimeRange: String, CaseIterable {
        case minutes10 = "10 Min"
        case minutes30 = "30 Min"
        case hour1 = "1 Hour"
        case hours6 = "6 Hours"
        
        var seconds: TimeInterval {
            switch self {
            case .minutes10: return 600
            case .minutes30: return 1800
            case .hour1: return 3600
            case .hours6: return 21600
            }
        }
        
        var maxDataPoints: Int {
            switch self {
            case .minutes10: return 120  // 5 second intervals
            case .minutes30: return 180  // 10 second intervals
            case .hour1: return 240      // 15 second intervals
            case .hours6: return 360     // 1 minute intervals
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with device selection
            List(selection: $selectedDevice) {
                Section("Monitored Devices") {
                    DeviceListItem(
                        deviceIndex: 1,
                        label: configuration.device1Label,
                        isActive: monitor.isMonitoring,
                        hasError: monitor.device1ErrorMessage != nil
                    )
                    .tag(1)
                    
                    if configuration.device2Enabled {
                        DeviceListItem(
                            deviceIndex: 2,
                            label: configuration.device2Label,
                            isActive: monitor.isMonitoring,
                            hasError: monitor.device2ErrorMessage != nil
                        )
                        .tag(2)
                    }
                    
                    if configuration.lanEnabled {
                        DeviceListItem(
                            deviceIndex: 3,
                            label: configuration.lanLabel,
                            isActive: monitor.isMonitoring,
                            hasError: monitor.lanErrorMessage != nil
                        )
                        .tag(3)
                    }
                }
                
                Section("Views") {
                    Label("Overview", systemImage: "chart.bar.fill")
                        .tag(0)
                    Label("Comparison", systemImage: "chart.line.uptrend.xyaxis")
                        .tag(10)
                    Label("Alerts", systemImage: "bell.badge.fill")
                        .tag(20)
                        .badge(monitor.activeAlertCount)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { @MainActor in
                            if monitor.isMonitoring {
                                monitor.stopMonitoring()
                            } else {
                                monitor.startMonitoring()
                            }
                        }
                    } label: {
                        Label(
                            monitor.isMonitoring ? "Stop" : "Start",
                            systemImage: monitor.isMonitoring ? "stop.circle" : "play.circle"
                        )
                    }
                }
            }
        } detail: {
            // Main content area
            if selectedDevice < 10 {
                // Individual device view
                DeviceDetailView(
                    monitor: monitor,
                    deviceIndex: selectedDevice,
                    timeRange: $selectedTimeRange
                )
            } else if selectedDevice == 10 {
                // Comparison view
                ComparisonDashboardView(monitor: monitor)
            } else if selectedDevice == 20 {
                // Alerts view
                AlertsDashboardView()
            } else {
                // Overview (default)
                OverviewDashboardView(monitor: monitor)
            }
        }
        .navigationTitle("WAN Monitor Dashboard")
        .frame(minWidth: 1000, minHeight: 600)
    }
}

// MARK: - Device List Item

struct DeviceListItem: View {
    let deviceIndex: Int
    let label: String
    let isActive: Bool
    let hasError: Bool
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(statusColor)
            
            Text(label)
            
            Spacer()
            
            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private var iconName: String {
        switch deviceIndex {
        case 3: return "network"
        default: return "antenna.radiowaves.left.and.right"
        }
    }
    
    private var statusColor: Color {
        if hasError { return .orange }
        if isActive { return .green }
        return .secondary
    }
}

// MARK: - Device Detail View

struct DeviceDetailView: View {
    @ObservedObject var monitor: ConnectionMonitor
    let deviceIndex: Int
    @Binding var timeRange: DashboardView.DashboardTimeRange
    @ObservedObject var historyManager = HistoryManager.shared
    
    private var deviceLabel: String {
        let config = NetworkConfiguration.shared
        switch deviceIndex {
        case 1: return config.device1Label
        case 2: return config.device2Label
        case 3: return config.lanLabel
        default: return "Unknown"
        }
    }
    
    private var currentUpload: (value: String, unit: String) {
        switch deviceIndex {
        case 1: return monitor.device1FormattedUploadSpeed
        case 2: return monitor.device2FormattedUploadSpeed
        case 3: return monitor.lanFormattedUploadSpeed
        default: return ("0", "Mbps")
        }
    }
    
    private var currentDownload: (value: String, unit: String) {
        switch deviceIndex {
        case 1: return monitor.device1FormattedDownloadSpeed
        case 2: return monitor.device2FormattedDownloadSpeed
        case 3: return monitor.lanFormattedDownloadSpeed
        default: return ("0", "Mbps")
        }
    }
    
    private var currentLatency: String {
        switch deviceIndex {
        case 1: return monitor.device1FormattedLatency
        case 2: return monitor.device2FormattedLatency
        default: return "-"
        }
    }
    
    private var currentPacketLoss: String {
        switch deviceIndex {
        case 1: return monitor.device1FormattedPacketLoss
        case 2: return monitor.device2FormattedPacketLoss
        default: return "-"
        }
    }
    
    private var errorMessage: String? {
        switch deviceIndex {
        case 1: return monitor.device1ErrorMessage
        case 2: return monitor.device2ErrorMessage
        case 3: return monitor.lanErrorMessage
        default: return nil
        }
    }
    
    private var deviceUptime: String {
        switch deviceIndex {
        case 1: return monitor.device1DeviceUptime
        case 2: return monitor.device2DeviceUptime
        default: return "-"
        }
    }
    
    private var rebootDetected: Bool {
        switch deviceIndex {
        case 1: return monitor.device1RebootDetected
        case 2: return monitor.device2RebootDetected
        default: return false
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time Range Selector
                Picker("Time Range", selection: $timeRange) {
                    ForEach(DashboardView.DashboardTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Current Status Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    RealTimeStatCard(
                        title: "Upload",
                        value: currentUpload.value,
                        unit: currentUpload.unit,
                        icon: "arrow.up.circle.fill",
                        color: .red
                    )
                    
                    RealTimeStatCard(
                        title: "Download",
                        value: currentDownload.value,
                        unit: currentDownload.unit,
                        icon: "arrow.down.circle.fill",
                        color: .blue
                    )
                    
                    if deviceIndex != 3 {
                        RealTimeStatCard(
                            title: "Latency",
                            value: currentLatency,
                            unit: "ms",
                            icon: "timer",
                            color: .green
                        )
                        
                        RealTimeStatCard(
                            title: "Packet Loss",
                            value: currentPacketLoss,
                            unit: "",
                            icon: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal)
                
                // Device uptime row (WAN devices only)
                if deviceIndex != 3 {
                    GroupBox {
                        HStack(spacing: 16) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Device Uptime")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(deviceUptime)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            if rebootDetected {
                                Spacer()
                                Label("Reboot detected", systemImage: "exclamationmark.arrow.circlepath")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Error message if present
                if let error = errorMessage {
                    GroupBox {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Troubleshoot") {
                                // Open troubleshooting
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Real-time graphs
                VStack(spacing: 16) {
                    // Upload/Download Combined Graph
                    GroupBox("Traffic") {
                        RealTimeTrafficChart(
                            deviceIndex: deviceIndex,
                            timeRange: timeRange
                        )
                        .frame(height: 200)
                    }
                    
                    // Latency Graph (if applicable)
                    if deviceIndex != 3 {
                        GroupBox("Latency & Packet Loss") {
                            RealTimeLatencyChart(
                                deviceIndex: deviceIndex,
                                timeRange: timeRange
                            )
                            .frame(height: 150)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Quick Stats
                GroupBox("Statistics (\(timeRange.rawValue))") {
                    QuickStatsView(
                        deviceIndex: deviceIndex,
                        timeRange: timeRange
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(deviceLabel)
    }
}

// MARK: - Real-Time Stat Card

struct RealTimeStatCard: View {
    let title: String
    let value: String
    let unit: String
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
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Real-Time Traffic Chart

struct RealTimeTrafficChart: View {
    let deviceIndex: Int
    let timeRange: DashboardView.DashboardTimeRange
    @ObservedObject var historyManager = HistoryManager.shared
    
    private var recentHistory: [NetworkDataPoint] {
        let history: [NetworkDataPoint]
        switch deviceIndex {
        case 1: history = historyManager.device1History
        case 2: history = historyManager.device2History
        case 3: history = historyManager.lanHistory
        default: return []
        }
        
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return history.filter { $0.timestamp >= cutoff }
    }
    
    var body: some View {
        Chart {
            ForEach(recentHistory) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Download", point.downloadSpeed * 8 / 1_000_000)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Upload", point.uploadSpeed * 8 / 1_000_000)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel("Mbps")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartLegend {
            HStack(spacing: 16) {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Label("Upload", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
    }
}

// MARK: - Real-Time Latency Chart

struct RealTimeLatencyChart: View {
    let deviceIndex: Int
    let timeRange: DashboardView.DashboardTimeRange
    @ObservedObject var historyManager = HistoryManager.shared
    
    private var recentHistory: [NetworkDataPoint] {
        let history: [NetworkDataPoint]
        switch deviceIndex {
        case 1: history = historyManager.device1History
        case 2: history = historyManager.device2History
        default: return []
        }
        
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return history.filter { $0.timestamp >= cutoff && $0.latency != nil }
    }
    
    var body: some View {
        Chart {
            ForEach(recentHistory) { point in
                if let latency = point.latency {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Latency", latency)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartYAxisLabel("Latency (ms)")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
    }
}

// MARK: - Quick Stats View

struct QuickStatsView: View {
    let deviceIndex: Int
    let timeRange: DashboardView.DashboardTimeRange
    @ObservedObject var historyManager = HistoryManager.shared
    
    private var recentHistory: [NetworkDataPoint] {
        let history: [NetworkDataPoint]
        switch deviceIndex {
        case 1: history = historyManager.device1History
        case 2: history = historyManager.device2History
        case 3: history = historyManager.lanHistory
        default: return []
        }
        
        let cutoff = Date().addingTimeInterval(-timeRange.seconds)
        return history.filter { $0.timestamp >= cutoff }
    }
    
    private var stats: (avgUp: Double, maxUp: Double, avgDown: Double, maxDown: Double, avgLatency: Double?, maxLatency: Double?) {
        guard !recentHistory.isEmpty else {
            return (0, 0, 0, 0, nil, nil)
        }
        
        let uploadSpeeds = recentHistory.map { $0.uploadSpeed * 8 / 1_000_000 }
        let downloadSpeeds = recentHistory.map { $0.downloadSpeed * 8 / 1_000_000 }
        let latencies = recentHistory.compactMap { $0.latency }
        
        return (
            uploadSpeeds.reduce(0, +) / Double(uploadSpeeds.count),
            uploadSpeeds.max() ?? 0,
            downloadSpeeds.reduce(0, +) / Double(downloadSpeeds.count),
            downloadSpeeds.max() ?? 0,
            latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
            latencies.max()
        )
    }
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Text("Average Upload:")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f Mbps", stats.avgUp))
                    .monospacedDigit()
                
                Text("Maximum Upload:")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f Mbps", stats.maxUp))
                    .monospacedDigit()
            }
            
            GridRow {
                Text("Average Download:")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f Mbps", stats.avgDown))
                    .monospacedDigit()
                
                Text("Maximum Download:")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f Mbps", stats.maxDown))
                    .monospacedDigit()
            }
            
            if let avgLatency = stats.avgLatency, let maxLatency = stats.maxLatency {
                GridRow {
                    Text("Average Latency:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f ms", avgLatency))
                        .monospacedDigit()
                    
                    Text("Maximum Latency:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f ms", maxLatency))
                        .monospacedDigit()
                }
            }
            
            GridRow {
                Text("Data Points:")
                    .foregroundStyle(.secondary)
                Text("\(recentHistory.count)")
                    .monospacedDigit()
                
                Text("")
                Text("")
            }
        }
        .padding()
    }
}

// MARK: - Overview Dashboard

struct OverviewDashboardView: View {
    @ObservedObject var monitor: ConnectionMonitor
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Network Overview")
                    .font(.largeTitle)
                    .padding()
                
                Text("Select a device from the sidebar to view detailed information")
                    .foregroundStyle(.secondary)
                
                // Could add summary cards for all devices here
            }
        }
    }
}

// MARK: - Comparison Dashboard

struct ComparisonDashboardView: View {
    @ObservedObject var monitor: ConnectionMonitor
    @ObservedObject var historyManager = HistoryManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("WAN Comparison")
                    .font(.largeTitle)
                    .padding()
                
                // Side-by-side comparison of WAN links
                GroupBox("Download Speed Comparison") {
                    Chart {
                        ForEach(historyManager.device1History.suffix(100)) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Speed", point.downloadSpeed * 8 / 1_000_000)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                        }
                        
                        ForEach(historyManager.device2History.suffix(100)) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Speed", point.downloadSpeed * 8 / 1_000_000)
                            )
                            .foregroundStyle(.red)
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .frame(height: 200)
                    .chartYAxisLabel("Mbps")
                }
                .padding()
            }
        }
    }
}

// MARK: - Alerts Dashboard

struct AlertsDashboardView: View {
    var body: some View {
        ContentUnavailableView(
            "No Active Alerts",
            systemImage: "bell.slash",
            description: Text("Your network is performing normally")
        )
    }
}

#Preview {
    DashboardView(monitor: ConnectionMonitor())
        .frame(width: 1200, height: 800)
}
