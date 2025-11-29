//
//  SettingsView.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var configuration = NetworkConfiguration.shared
    @ObservedObject var monitor: ConnectionMonitor
    let onClose: () -> Void
    
    @State private var showingDevice1InterfaceDiscovery = false
    @State private var showingDevice2InterfaceDiscovery = false
    @State private var interfaceDiscoveryWindow: NSWindow?
    
    @State private var showAdvancedSettings = false
    @State private var showClearHistoryConfirmation = false
    
    private var estimatedDataPoints: Int {
        let retentionSeconds = configuration.historyRetentionMinutes * 60
        let updateInterval = configuration.updateInterval
        return Int(Double(retentionSeconds) / updateInterval)
    }
    
    private var estimatedMemoryUsageMB: Int {
        // Rough estimate: 48 bytes per data point (UUID + Date + 3 Doubles) + overhead
        // Using conservative 100 bytes per point including array overhead
        let bytesPerPoint = 100
        let totalBytes = estimatedDataPoints * bytesPerPoint
        return totalBytes / (1024 * 1024)
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                NavigationLink(destination: DevicesSettingsView()) {
                    Label("Devices", systemImage: "shield")
                }
                
                NavigationLink(destination: MonitoringSettingsView()) {
                    Label("Monitoring", systemImage: "chart.line.uptrend.xyaxis")
                }
                
                if monitor.isMonitoring {
                    NavigationLink(destination: StatusView()) {
                        Label("Status", systemImage: "checkmark.circle")
                    }
                    
                    NavigationLink(destination: NetworkHistoryView(deviceIndex: 1)) {
                        Label("\(configuration.device1Label) History", systemImage: "chart.xyaxis.line")
                    }
                    
                    if configuration.device2Enabled {
                        NavigationLink(destination: NetworkHistoryView(deviceIndex: 2)) {
                            Label("\(configuration.device2Label) History", systemImage: "chart.xyaxis.line")
                        }
                    }
                    
                    if configuration.lanEnabled {
                        NavigationLink(destination: NetworkHistoryView(deviceIndex: 3)) {
                            Label("\(configuration.lanLabel) History", systemImage: "chart.xyaxis.line")
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            // Default detail view
            DevicesSettingsView()
        }
        .navigationTitle("WAN Monitor Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onClose()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    configuration.saveConfiguration()
                    // Restart monitoring with new settings
                    Task {
                        monitor.stopMonitoring()
                        monitor.startMonitoring()
                    }
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    // MARK: - Device Settings View
    @ViewBuilder
    private func DevicesSettingsView() -> some View {
        Form {
            Section {
                DeviceConfigurationCard(
                    deviceNumber: 1,
                    isEnabled: .constant(true), // Device 1 is always enabled
                    configuration: configuration,
                    monitor: monitor,
                    showInterfaceDiscovery: { showInterfaceDiscovery(for: 1) }
                )
            } header: {
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Primary Device")
                        .font(.headline)
                }
            }
            
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Toggle("Enable Secondary Device", isOn: $configuration.device2Enabled)
                            .font(.headline)
                        Spacer()
                    }
                    
                    if configuration.device2Enabled {
                        DeviceConfigurationCard(
                            deviceNumber: 2,
                            isEnabled: $configuration.device2Enabled,
                            configuration: configuration,
                            monitor: monitor,
                            showInterfaceDiscovery: { showInterfaceDiscovery(for: 2) }
                        )
                    } else {
                        Text("Enable secondary device monitoring to configure additional network equipment.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Secondary Device")
                        .font(.headline)
                }
            }
            
            Section {
                VStack(spacing: 12) {
                    HStack {
                        Toggle("Enable Local LAN Monitoring", isOn: $configuration.lanEnabled)
                            .font(.headline)
                        Spacer()
                    }
                    
                    if configuration.lanEnabled {
                        LANConfigurationCard(
                            configuration: configuration,
                            monitor: monitor,
                            showInterfaceDiscovery: { showLANInterfaceDiscovery() }
                        )
                    } else {
                        Text("Enable local LAN monitoring to track your Mac's network interface usage.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "network")
                        .foregroundStyle(.green)
                    Text("Local LAN Interface")
                        .font(.headline)
                }
            } footer: {
                Text("Monitor your Mac's local network interface without requiring SNMP. This tracks data from the system's built-in network statistics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
    
    // MARK: - Monitoring Settings View
    @ViewBuilder 
    private func MonitoringSettingsView() -> some View {
        Form {
            Section("Update Frequency") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Update Interval")
                        Spacer()
                        Text("\(configuration.updateInterval, specifier: "%.1f") seconds")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: $configuration.updateInterval,
                        in: 1.0...10.0,
                        step: 0.5
                    ) {
                        Text("Update Interval")
                    } minimumValueLabel: {
                        Text("1s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("10s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Display Options") {
                Picker("Speed Unit", selection: $configuration.speedDisplayUnit) {
                    ForEach(SpeedDisplayUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Section("Startup Behavior") {
                Toggle("Start monitoring automatically on launch", isOn: $configuration.autoStartMonitoring)
                    .onChange(of: configuration.autoStartMonitoring) { _, _ in
                        configuration.saveConfiguration()
                    }
                
                Toggle("Start app at login", isOn: $configuration.startAtLogin)
                    .onChange(of: configuration.startAtLogin) { _, _ in
                        configuration.saveConfiguration()
                    }
            }
            
            // MARK: - History Settings
            GroupBox(label: Label("History", systemImage: "clock.arrow.circlepath")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Keep history for:")
                        Picker("", selection: $configuration.historyRetentionMinutes) {
                            Text("5 minutes").tag(5)
                            Text("10 minutes").tag(10)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("6 hours").tag(360)
                            Text("12 hours").tag(720)
                            Text("24 hours").tag(1440)
                            Text("3 days").tag(4320)
                            Text("7 days").tag(10080)
                            Text("14 days").tag(20160)
                            Text("30 days").tag(43200)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .onChange(of: configuration.historyRetentionMinutes) { _, _ in
                        configuration.saveConfiguration()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approximate data points: \(estimatedDataPoints)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if estimatedMemoryUsageMB > 100 {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                                Text("Estimated memory usage: ~\(estimatedMemoryUsageMB) MB per device")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Toggle("Save history when quitting app", isOn: $configuration.historySaveOnQuit)
                        .onChange(of: configuration.historySaveOnQuit) { _, _ in
                            configuration.saveConfiguration()
                        }
                    
                    Toggle("Load history on startup", isOn: $configuration.historyLoadOnStartup)
                        .onChange(of: configuration.historyLoadOnStartup) { _, _ in
                            configuration.saveConfiguration()
                        }
                    
                    if configuration.historyLoadOnStartup {
                        HStack {
                            Text("Keep history older than:")
                            Picker("", selection: $configuration.historyRetentionHoursOnStartup) {
                                Text("1 hour").tag(1)
                                Text("6 hours").tag(6)
                                Text("12 hours").tag(12)
                                Text("24 hours").tag(24)
                                Text("3 days").tag(72)
                                Text("1 week").tag(168)
                                Text("2 weeks").tag(336)
                                Text("30 days").tag(720)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        .onChange(of: configuration.historyRetentionHoursOnStartup) { _, _ in
                            configuration.saveConfiguration()
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Button(role: .destructive) {
                            showClearHistoryConfirmation = true
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                        .confirmationDialog(
                            "Clear all history data?",
                            isPresented: $showClearHistoryConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Clear Device 1 History", role: .destructive) {
                                HistoryManager.shared.clearHistory(device: 1)
                            }
                            Button("Clear Device 2 History", role: .destructive) {
                                HistoryManager.shared.clearHistory(device: 2)
                            }
                            Button("Clear All History", role: .destructive) {
                                HistoryManager.shared.clearHistory()
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                        
                        Spacer()
                    }
                }
                .padding(8)
            }
            
            Section("Network Testing") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ping Interval")
                        Spacer()
                        Text("\(configuration.pingInterval, specifier: "%.1f") seconds")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: $configuration.pingInterval,
                        in: 2.0...30.0,
                        step: 1.0
                    ) {
                        Text("Ping Interval")
                    } minimumValueLabel: {
                        Text("2s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("30s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("How often to ping the target hosts for latency measurement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                LabeledContent("Ping Target (Device 1)") {
                    TextField("8.8.8.8", text: $configuration.pingHost1)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                }
                
                if configuration.device2Enabled {
                    LabeledContent("Ping Target (Device 2)") {
                        TextField("1.1.1.1", text: $configuration.pingHost2)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                    }
                }
                
                Divider()
                
                LatencyColorSettingsCard(deviceIndex: 1, configuration: configuration)
                
                if configuration.device2Enabled {
                    LatencyColorSettingsCard(deviceIndex: 2, configuration: configuration)
                }
            }
            
            Section {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
    
    // MARK: - Status View
    @ViewBuilder
    private func StatusView() -> some View {
        Form {
            if monitor.isMonitoring {
                Section("Device Status") {
                    DeviceStatusCard(
                        deviceName: configuration.device1Label,
                        deviceHost: configuration.device1Host,
                        errorMessage: monitor.device1ErrorMessage,
                        interfaceCount: monitor.device1AvailableInterfaces.count,
                        uploadSpeed: monitor.device1FormattedUploadSpeed,
                        downloadSpeed: monitor.device1FormattedDownloadSpeed,
                        latency: monitor.device1FormattedLatency
                    )
                    
                    if configuration.device2Enabled {
                        DeviceStatusCard(
                            deviceName: configuration.device2Label,
                            deviceHost: configuration.device2Host,
                            errorMessage: monitor.device2ErrorMessage,
                            interfaceCount: monitor.device2AvailableInterfaces.count,
                            uploadSpeed: monitor.device2FormattedUploadSpeed,
                            downloadSpeed: monitor.device2FormattedDownloadSpeed,
                            latency: monitor.device2FormattedLatency
                        )
                    }
                    
                    if configuration.lanEnabled {
                        LANStatusCard(
                            deviceName: configuration.lanLabel,
                            interfaceName: configuration.lanInterfaceName,
                            errorMessage: monitor.lanErrorMessage,
                            uploadSpeed: monitor.lanFormattedUploadSpeed,
                            downloadSpeed: monitor.lanFormattedDownloadSpeed
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Monitoring Stopped",
                    systemImage: "pause.circle",
                    description: Text("Start monitoring to view device status")
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Status")
    }
    
    // MARK: - Helper Methods
    
    private func resetToDefaults() {
        configuration.device1Host = "192.168.86.1"
        configuration.device1Community = "public"
        configuration.device1Port = 161
        configuration.device1Label = "HW"
        configuration.device1InterfaceName = ""
        
        configuration.device2Host = "192.168.87.1"
        configuration.device2Community = "public"
        configuration.device2Port = 161
        configuration.device2Label = "PW"
        configuration.device2InterfaceName = ""
        configuration.device2Enabled = true
        
        configuration.pingHost1 = "8.8.8.8"
        configuration.pingHost2 = "1.1.1.1"
        configuration.updateInterval = 2.0
        configuration.speedDisplayUnit = .bits
        configuration.autoStartMonitoring = false
        configuration.startAtLogin = false
        
        // Save the reset configuration
        configuration.saveConfiguration()
    }
    
    private func showInterfaceDiscovery(for deviceIndex: Int) {
        // Close existing window if open
        interfaceDiscoveryWindow?.close()
        interfaceDiscoveryWindow = nil
        
        // Create new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let discoveryView = InterfaceDiscoveryView(monitor: monitor, deviceIndex: deviceIndex)
        let hostingController = NSHostingController(rootView: discoveryView)
        
        window.title = "Interface Discovery - Device \(deviceIndex)"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("InterfaceDiscovery")
        window.isReleasedWhenClosed = false
        
        interfaceDiscoveryWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func showLANInterfaceDiscovery() {
        // Close existing window if open
        interfaceDiscoveryWindow?.close()
        interfaceDiscoveryWindow = nil
        
        // Create new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let discoveryView = LANInterfaceDiscoveryView(monitor: monitor)
        let hostingController = NSHostingController(rootView: discoveryView)
        
        window.title = "Local LAN Interface Discovery"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("LANInterfaceDiscovery")
        window.isReleasedWhenClosed = false
        
        interfaceDiscoveryWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Device Configuration Card

struct DeviceConfigurationCard: View {
    let deviceNumber: Int
    @Binding var isEnabled: Bool
    @ObservedObject var configuration: NetworkConfiguration
    @ObservedObject var monitor: ConnectionMonitor
    let showInterfaceDiscovery: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Device Label and Host
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Label")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("Device Name", text: deviceNumber == 1 ? $configuration.device1Label : $configuration.device2Label)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP Address")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("192.168.1.1", text: deviceNumber == 1 ? $configuration.device1Host : $configuration.device2Host)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // SNMP Configuration
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Community String")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    SecureField("public", text: deviceNumber == 1 ? $configuration.device1Community : $configuration.device2Community)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("SNMP Port")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("161", value: deviceNumber == 1 ? $configuration.device1Port : $configuration.device2Port, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // Interface Configuration
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Interface")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("Auto-detect", text: deviceNumber == 1 ? $configuration.device1InterfaceName : $configuration.device2InterfaceName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack {
                    Spacer()
                    Button("Discover") {
                        showInterfaceDiscovery()
                    }
                    .buttonStyle(.bordered)
                    .disabled(deviceNumber == 1 ? configuration.device1Host.isEmpty : configuration.device2Host.isEmpty)
                }
            }
            
            // Interface Status
            let interfaces = deviceNumber == 1 ? monitor.device1AvailableInterfaces : monitor.device2AvailableInterfaces
            if !interfaces.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Found \(interfaces.count) interfaces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    let upInterfaces = interfaces.filter { $0.operStatus == "Up" }
                    if !upInterfaces.isEmpty {
                        Text("• \(upInterfaces.count) active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Device Status Card

struct DeviceStatusCard: View {
    let deviceName: String
    let deviceHost: String
    let errorMessage: String?
    let interfaceCount: Int
    let uploadSpeed: (value: String, unit: String)
    let downloadSpeed: (value: String, unit: String)
    let latency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .font(.headline)
                    Text(deviceHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(errorMessage == nil ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(errorMessage == nil ? "Connected" : "Error")
                        .font(.caption)
                        .foregroundStyle(errorMessage == nil ? .green : .red)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Metrics
            HStack(spacing: 20) {
                MetricView(
                    title: "Upload",
                    value: uploadSpeed.value,
                    unit: uploadSpeed.unit,
                    systemImage: "arrow.up"
                )
                
                MetricView(
                    title: "Download", 
                    value: downloadSpeed.value,
                    unit: downloadSpeed.unit,
                    systemImage: "arrow.down"
                )
                
                MetricView(
                    title: "Latency",
                    value: latency,
                    unit: "ms",
                    systemImage: "timer"
                )
                
                Spacer()
                
                if interfaceCount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(interfaceCount)")
                            .font(.title3)
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Text("interfaces")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - LAN Status Card

struct LANStatusCard: View {
    let deviceName: String
    let interfaceName: String
    let errorMessage: String?
    let uploadSpeed: (value: String, unit: String)
    let downloadSpeed: (value: String, unit: String)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .font(.headline)
                    Text(interfaceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(errorMessage == nil ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(errorMessage == nil ? "Active" : "Error")
                        .font(.caption)
                        .foregroundStyle(errorMessage == nil ? .green : .red)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Metrics
            HStack(spacing: 20) {
                MetricView(
                    title: "Upload",
                    value: uploadSpeed.value,
                    unit: uploadSpeed.unit,
                    systemImage: "arrow.up"
                )
                
                MetricView(
                    title: "Download", 
                    value: downloadSpeed.value,
                    unit: downloadSpeed.unit,
                    systemImage: "arrow.down"
                )
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Local Interface")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Metric View

struct MetricView: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(monitor: ConnectionMonitor()) {
            // Empty closure for preview
        }
    }
}

// MARK: - Latency Color Settings Card

struct LatencyColorSettingsCard: View {
    let deviceIndex: Int
    @ObservedObject var configuration: NetworkConfiguration
    
    private var colorEnabled: Binding<Bool> {
        deviceIndex == 1 ? $configuration.device1LatencyColorEnabled : $configuration.device2LatencyColorEnabled
    }
    
    private var warningThreshold: Binding<Double> {
        deviceIndex == 1 ? $configuration.device1LatencyWarningThreshold : $configuration.device2LatencyWarningThreshold
    }
    
    private var criticalThreshold: Binding<Double> {
        deviceIndex == 1 ? $configuration.device1LatencyCriticalThreshold : $configuration.device2LatencyCriticalThreshold
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Device \(deviceIndex) Latency Colors")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: colorEnabled)
                    .labelsHidden()
            }
            
            if colorEnabled.wrappedValue {
                VStack(alignment: .leading, spacing: 16) {
                    // Warning threshold
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Warning Threshold")
                                .font(.subheadline)
                            Spacer()
                            Text("\(warningThreshold.wrappedValue, specifier: "%.0f") ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: warningThreshold,
                            in: 10.0...200.0,
                            step: 5.0
                        ) {
                            Text("Warning Threshold")
                        } minimumValueLabel: {
                            Text("10")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("200")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Critical threshold
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("Critical Threshold")
                                .font(.subheadline)
                            Spacer()
                            Text("\(criticalThreshold.wrappedValue, specifier: "%.0f") ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: criticalThreshold,
                            in: 20.0...500.0,
                            step: 10.0
                        ) {
                            Text("Critical Threshold")
                        } minimumValueLabel: {
                            Text("20")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("500")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Preview
                    HStack(spacing: 12) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.white)
                            .font(.caption)
                        Text("Good: < \(warningThreshold.wrappedValue, specifier: "%.0f") ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("\(warningThreshold.wrappedValue, specifier: "%.0f")-\(criticalThreshold.wrappedValue, specifier: "%.0f") ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("> \(criticalThreshold.wrappedValue, specifier: "%.0f") ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 8)
            } else {
                Text("Latency will be displayed without color coding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - LAN Configuration Card

struct LANConfigurationCard: View {
    @ObservedObject var configuration: NetworkConfiguration
    @ObservedObject var monitor: ConnectionMonitor
    let showInterfaceDiscovery: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // LAN Label and Interface
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAN Label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Label", text: $configuration.lanLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Interface")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("en0", text: $configuration.lanInterfaceName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        
                        Button {
                            showInterfaceDiscovery()
                        } label: {
                            Label("Discover", systemImage: "magnifyingglass")
                        }
                        .help("Discover available network interfaces on this Mac")
                    }
                    Text("Tip: For bonded connections, use comma-separated names (e.g., \"en0, en1\")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            // Currently Selected Interface Info
            if monitor.lanAvailableInterfaces.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Click 'Discover' to find available network interfaces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedInterface = monitor.lanAvailableInterfaces.first(where: { $0.name == configuration.lanInterfaceName }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Selected Interface:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedInterface.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack(spacing: 12) {
                        if let ipAddress = selectedInterface.ipAddress {
                            Label(ipAddress, systemImage: "network")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Label(selectedInterface.isActive ? "Active" : "Inactive", 
                              systemImage: selectedInterface.isActive ? "checkmark.circle" : "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(selectedInterface.isActive ? .green : .secondary)
                    }
                }
                .padding(.horizontal)
            } else if !configuration.lanInterfaceName.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Interface '\(configuration.lanInterfaceName)' not found. Click 'Discover' to find available interfaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - LAN Interface Discovery View

struct LANInterfaceDiscoveryView: View {
    @ObservedObject var monitor: ConnectionMonitor
    @State private var isDiscovering = false
    @State private var selectedInterface: LocalInterface?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discover Local Network Interfaces")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Select the network interface you want to monitor")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                Button {
                    discoverInterfaces()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isDiscovering)
            }
            .padding()
            
            Divider()
            
            // Interface List
            if isDiscovering {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Discovering network interfaces...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if monitor.lanAvailableInterfaces.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No network interfaces found")
                        .font(.headline)
                    Text("Click 'Refresh' to discover interfaces")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(monitor.lanAvailableInterfaces, selection: $selectedInterface) { interface in
                    LANInterfaceRow(interface: interface)
                        .tag(interface)
                }
            }
            
            Divider()
            
            // Footer with action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Use Selected Interface") {
                    if let selectedInterface = selectedInterface {
                        NetworkConfiguration.shared.lanInterfaceName = selectedInterface.name
                        NetworkConfiguration.shared.saveConfiguration()
                        dismiss()
                    }
                }
                .disabled(selectedInterface == nil)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            discoverInterfaces()
        }
    }
    
    private func discoverInterfaces() {
        isDiscovering = true
        
        Task {
            await monitor.discoverLANInterfaces()
            
            await MainActor.run {
                isDiscovering = false
                
                // Pre-select current interface if it exists
                if let currentInterfaceName = NetworkConfiguration.shared.lanInterfaceName.isEmpty ? nil : NetworkConfiguration.shared.lanInterfaceName,
                   let current = monitor.lanAvailableInterfaces.first(where: { $0.name == currentInterfaceName }) {
                    selectedInterface = current
                } else if let firstActive = monitor.lanAvailableInterfaces.first(where: { $0.isActive }) {
                    // Otherwise select the first active interface
                    selectedInterface = firstActive
                }
            }
        }
    }
}

struct LANInterfaceRow: View {
    let interface: LocalInterface
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(interface.isActive ? Color.green : Color.secondary)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(interface.displayName)
                        .font(.headline)
                    
                    Text("(\(interface.name))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if interface.isActive {
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                    }
                }
                
                if let ipAddress = interface.ipAddress {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ipAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}