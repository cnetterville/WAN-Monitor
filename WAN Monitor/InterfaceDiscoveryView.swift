//
//  InterfaceDiscoveryView.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import SwiftUI

struct InterfaceDiscoveryView: View {
    @ObservedObject var monitor: ConnectionMonitor
    let deviceIndex: Int
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedInterface: NetworkInterface?
    
    private var deviceLabel: String {
        return deviceIndex == 1 ? NetworkConfiguration.shared.device1Label : NetworkConfiguration.shared.device2Label
    }
    
    private var availableInterfaces: [NetworkInterface] {
        return deviceIndex == 1 ? monitor.device1AvailableInterfaces : monitor.device2AvailableInterfaces
    }
    
    private var isDiscovering: Bool {
        return deviceIndex == 1 ? monitor.device1IsDiscoveringInterfaces : monitor.device2IsDiscoveringInterfaces
    }
    
    private var errorMessage: String? {
        return deviceIndex == 1 ? monitor.device1ErrorMessage : monitor.device2ErrorMessage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Interface Discovery - Device \(deviceIndex) (\(deviceLabel))")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            
            // Status and Controls
            HStack {
                if isDiscovering {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Discovering interfaces...")
                        .foregroundColor(.secondary)
                } else {
                    Button("Refresh") {
                        Task {
                            await monitor.discoverInterfaces(for: deviceIndex)
                        }
                    }
                    
                    if !availableInterfaces.isEmpty {
                        Text("Found \(availableInterfaces.count) interfaces")
                            .foregroundColor(.secondary)
                            .padding(.leading)
                    }
                }
                Spacer()
            }
            
            // Content
            if let errorMessage = errorMessage {
                VStack(spacing: 15) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Discovery Failed")
                        .font(.headline)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Retry") {
                        Task {
                            await monitor.discoverInterfaces(for: deviceIndex)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if availableInterfaces.isEmpty && !isDiscovering {
                VStack(spacing: 15) {
                    Image(systemName: "network.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No Interfaces Found")
                        .font(.headline)
                    Text("Click 'Refresh' to discover network interfaces on device \(deviceIndex) (\(NetworkConfiguration.shared.device1Host)).")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Start Discovery") {
                        Task {
                            await monitor.discoverInterfaces(for: deviceIndex)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                // Interface List with priority for "Up" interfaces
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Show "Up" interfaces first
                        let upInterfaces = availableInterfaces.filter { $0.operStatus == "Up" }
                        let downInterfaces = availableInterfaces.filter { $0.operStatus != "Up" }
                        
                        if !upInterfaces.isEmpty {
                            Text("Active Interfaces (\(upInterfaces.count))")
                                .font(.headline)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top)
                            
                            ForEach(upInterfaces) { interface in
                                InterfaceRow(
                                    interface: interface,
                                    isSelected: selectedInterface?.id == interface.id
                                ) {
                                    selectedInterface = interface
                                }
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        
                        if !downInterfaces.isEmpty {
                            Text("Inactive Interfaces (\(downInterfaces.count))")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top)
                            
                            ForEach(downInterfaces) { interface in
                                InterfaceRow(
                                    interface: interface,
                                    isSelected: selectedInterface?.id == interface.id
                                ) {
                                    selectedInterface = interface
                                }
                                .opacity(0.6)
                            }
                        }
                    }
                    .padding()
                }
                .frame(minHeight: 300)
            }
            
            // Selection Controls
            if let selectedInterface = selectedInterface {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected: \(selectedInterface.name)")
                            .font(.headline)
                        Text("Status: \(selectedInterface.operStatus)")
                            .font(.caption)
                            .foregroundColor(selectedInterface.operStatus == "Up" ? .green : .red)
                        if selectedInterface.operStatus == "Up" {
                            Text("✅ This interface is active and ready for monitoring")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("⚠️ This interface is inactive - monitoring may not work")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    Button("Use This Interface") {
                        print("DEBUG: InterfaceDiscovery - Selecting interface: \(selectedInterface.name) for device \(deviceIndex)")
                        if deviceIndex == 1 {
                            NetworkConfiguration.shared.device1InterfaceName = selectedInterface.name
                            print("DEBUG: Set device1InterfaceName to: \(selectedInterface.name)")
                        } else {
                            NetworkConfiguration.shared.device2InterfaceName = selectedInterface.name
                            print("DEBUG: Set device2InterfaceName to: \(selectedInterface.name)")
                        }
                        NetworkConfiguration.shared.saveConfiguration()
                        print("DEBUG: Configuration saved after interface selection")
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            // Always start fresh discovery when the view appears
            Task {
                await monitor.discoverInterfaces(for: deviceIndex)
            }
        }
    }
}

struct InterfaceRow: View {
    let interface: NetworkInterface
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 15) {
                // Status indicator
                Circle()
                    .fill(interface.operStatus == "Up" ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                // Interface info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(interface.name)
                            .font(.headline)
                            .fontWeight(interface.operStatus == "Up" ? .bold : .regular)
                        
                        if interface.operStatus == "Up" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Text("(Interface \(interface.index))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !interface.alias.isEmpty && interface.alias != interface.name {
                            Text("- \(interface.alias)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !interface.description.isEmpty && interface.description != interface.name {
                        Text(interface.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label(interface.operStatus, systemImage: interface.operStatus == "Up" ? "wifi" : "wifi.slash")
                            .foregroundColor(interface.operStatus == "Up" ? .green : .red)
                            .font(.caption)
                        
                        if interface.ipAddress != "N/A" {
                            Label(interface.ipAddress, systemImage: "network")
                                .font(.caption)
                        }
                        
                        if interface.speed != "N/A" {
                            Label(interface.speed, systemImage: "speedometer")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}