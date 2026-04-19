//
//  NotificationPreferencesView.swift
//  WAN Monitor
//
//  Settings view for notification preferences
//

import SwiftUI

struct NotificationPreferencesView: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationManager.notificationsEnabled)
                    .font(.headline)
                    .onChange(of: notificationManager.notificationsEnabled) { _, _ in
                        notificationManager.savePreferences()
                    }
            } header: {
                Label("Notifications", systemImage: "bell.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
            } footer: {
                Text("Receive system notifications for network events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if notificationManager.notificationsEnabled {
                Section("Notification Types") {
                    NotificationToggle(
                        title: "Connection Loss",
                        icon: "wifi.slash",
                        description: "Alert when a device becomes unreachable",
                        isOn: $notificationManager.connectionLossNotifications
                    )
                    
                    NotificationToggle(
                        title: "Connection Restored",
                        icon: "checkmark.circle",
                        description: "Notify when connection is re-established",
                        isOn: $notificationManager.connectionRestoredNotifications
                    )
                    
                    NotificationToggle(
                        title: "High Latency",
                        icon: "timer",
                        description: "Alert when latency exceeds thresholds",
                        isOn: $notificationManager.highLatencyNotifications
                    )
                    
                    NotificationToggle(
                        title: "Packet Loss",
                        icon: "exclamationmark.triangle",
                        description: "Notify when packet loss is detected",
                        isOn: $notificationManager.packetLossNotifications
                    )
                }
                
                Section("Sound") {
                    Toggle("Play Sound", isOn: $notificationManager.playSound)
                        .onChange(of: notificationManager.playSound) { _, _ in
                            notificationManager.savePreferences()
                        }
                }
                .onChange(of: notificationManager.connectionLossNotifications) { _, _ in
                    notificationManager.savePreferences()
                }
                .onChange(of: notificationManager.connectionRestoredNotifications) { _, _ in
                    notificationManager.savePreferences()
                }
                .onChange(of: notificationManager.highLatencyNotifications) { _, _ in
                    notificationManager.savePreferences()
                }
                .onChange(of: notificationManager.packetLossNotifications) { _, _ in
                    notificationManager.savePreferences()
                }
                
                Section {
                    HStack {
                        Spacer()
                        Button("Test Notification") {
                            testNotification()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                } footer: {
                    Text("Notifications may be throttled to prevent spam (max one per device per 5 minutes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func testNotification() {
        notificationManager.showNotification(
            title: "WAN Monitor Test",
            message: "Notifications are working correctly!",
            sound: notificationManager.playSound
        )
    }
}

struct NotificationToggle: View {
    let title: String
    let icon: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    Text(title)
                        .font(.body)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NotificationPreferencesView()
        .frame(width: 600, height: 500)
}
