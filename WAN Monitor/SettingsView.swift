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
                Toggle("Start monitoring automatically", isOn: $configuration.autoStartMonitoring)
                    .help("When enabled, monitoring will start automatically when the app launches")
                
                Toggle("Launch at login", isOn: $configuration.startAtLogin)
                    .help("When enabled, WAN Monitor will start automatically when you log in to your Mac")
            }
            
            Section("Network Testing") {
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