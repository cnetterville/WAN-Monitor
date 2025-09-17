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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("WAN Monitor Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    
                    Button("Reset Defaults") {
                        resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    
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
                
                // Device 1 Settings
                GroupBox(label: Text("Device 1 (\(configuration.device1Label))").font(.headline)) {
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Device Label")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("HW", text: $configuration.device1Label)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Host IP Address")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("192.168.86.1", text: $configuration.device1Host)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Community String")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            SecureField("public", text: $configuration.device1Community)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SNMP Port")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("161", value: $configuration.device1Port, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Interface Name")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("Leave empty for auto-detect", text: $configuration.device1InterfaceName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button("Discover") {
                                showInterfaceDiscovery(for: 1)
                            }
                            .disabled(configuration.device1Host.isEmpty)
                        }
                        
                        // Show current interface status
                        if !monitor.device1AvailableInterfaces.isEmpty {
                            Text("Found \(monitor.device1AvailableInterfaces.count) interfaces")
                                .font(.caption)
                                .foregroundColor(.green)
                            let upInterfaces = monitor.device1AvailableInterfaces.filter { $0.operStatus == "Up" }
                            if !upInterfaces.isEmpty {
                                Text("Active: \(upInterfaces.map { $0.name }.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 5)
                }
                
                // Device 2 Settings
                GroupBox(label: Text("Device 2 (\(configuration.device2Label))").font(.headline)) {
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Device Label")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("PW", text: $configuration.device2Label)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Host IP Address")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("192.168.87.1", text: $configuration.device2Host)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Community String")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            SecureField("public", text: $configuration.device2Community)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SNMP Port")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("161", value: $configuration.device2Port, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Interface Name")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("Leave empty for auto-detect", text: $configuration.device2InterfaceName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button("Discover") {
                                showInterfaceDiscovery(for: 2)
                            }
                            .disabled(configuration.device2Host.isEmpty)
                        }
                        
                        // Show current interface status
                        if !monitor.device2AvailableInterfaces.isEmpty {
                            Text("Found \(monitor.device2AvailableInterfaces.count) interfaces")
                                .font(.caption)
                                .foregroundColor(.green)
                            let upInterfaces = monitor.device2AvailableInterfaces.filter { $0.operStatus == "Up" }
                            if !upInterfaces.isEmpty {
                                Text("Active: \(upInterfaces.map { $0.name }.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 5)
                }
                
                // Monitoring Settings
                GroupBox(label: Text("Monitoring Settings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Update Interval: \(String(format: "%.1f", configuration.updateInterval)) seconds")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Slider(value: $configuration.updateInterval, in: 1.0...10.0, step: 0.5)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Speed Display Unit")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Picker("Speed Display Unit", selection: $configuration.speedDisplayUnit) {
                                ForEach(SpeedDisplayUnit.allCases, id: \.self) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Ping Host 1 (for \(configuration.device1Label))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("8.8.8.8", text: $configuration.pingHost1)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Ping Host 2 (for \(configuration.device2Label))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("1.1.1.1", text: $configuration.pingHost2)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 5)
                }
                
                // Current Status
                if monitor.isMonitoring {
                    GroupBox(label: Text("Current Status").font(.headline)) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Device 1 Status
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Device 1 (\(configuration.device1Label)) - \(configuration.device1Host):")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(monitor.device1ErrorMessage ?? "Connected")
                                    .foregroundColor(monitor.device1ErrorMessage != nil ? .red : .green)
                                    .padding(.leading)
                                
                                if !monitor.device1AvailableInterfaces.isEmpty {
                                    Text("Found \(monitor.device1AvailableInterfaces.count) interfaces")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading)
                                }
                            }
                            
                            Divider()
                            
                            // Device 2 Status
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Device 2 (\(configuration.device2Label)) - \(configuration.device2Host):")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(monitor.device2ErrorMessage ?? "Connected")
                                    .foregroundColor(monitor.device2ErrorMessage != nil ? .red : .green)
                                    .padding(.leading)
                                
                                if !monitor.device2AvailableInterfaces.isEmpty {
                                    Text("Found \(monitor.device2AvailableInterfaces.count) interfaces")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 700)
    }
    
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
        
        configuration.pingHost1 = "8.8.8.8"
        configuration.pingHost2 = "1.1.1.1"
        configuration.updateInterval = 2.0
        
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

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(monitor: ConnectionMonitor()) {
            // Empty closure for preview
        }
    }
}