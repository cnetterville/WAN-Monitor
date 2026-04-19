//
//  NotificationManager.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import UserNotifications
import Combine

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    // Notification preferences
    @Published var notificationsEnabled = true
    @Published var connectionLossNotifications = true
    @Published var highLatencyNotifications = true
    @Published var packetLossNotifications = true
    @Published var connectionRestoredNotifications = true
    @Published var playSound = true
    
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 300 // 5 minutes
    
    private init() {
        loadPreferences()
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DebugLogger.logUI("Notification permission granted")
            } else {
                DebugLogger.logUI("Notification permission denied")
            }
        }
    }
    
    // MARK: - Generic Notification Method
    
    func showNotification(title: String, message: String, identifier: String? = nil, sound: Bool = true) {
        guard notificationsEnabled else { return }
        
        let notifId = identifier ?? UUID().uuidString
        
        // Check cooldown for recurring notifications
        if identifier != nil {
            if let lastTime = lastNotificationTime[notifId],
               Date().timeIntervalSince(lastTime) < notificationCooldown {
                return
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if sound && playSound {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(identifier: notifId, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLogger.logError("Failed to send notification", error: error)
            } else {
                Task { @MainActor in
                    self.lastNotificationTime[notifId] = Date()
                }
            }
        }
    }
    
    // MARK: - Specific Notification Methods
    
    func notifyConnectionIssue(device: String, error: String) {
        guard connectionLossNotifications else { return }
        
        let identifier = "connection-loss-\(device)"
        showNotification(
            title: "⚠️ \(device) Connection Lost",
            message: error,
            identifier: identifier
        )
    }
    
    func notifyConnectionRestored(device: String) {
        guard connectionRestoredNotifications else { return }
        
        let identifier = "connection-restored-\(device)"
        showNotification(
            title: "✅ \(device) Connection Restored",
            message: "\(device) is now responding normally",
            identifier: identifier,
            sound: false // Don't play sound for good news
        )
        
        // Clear any existing connection loss notifications for this device
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["connection-loss-\(device)"])
    }
    
    func notifyHighLatency(device: String, latency: Double, threshold: Double) {
        guard highLatencyNotifications else { return }
        
        let identifier = "latency-\(device)"
        let severity = latency > threshold * 2 ? "Critical" : "High"
        
        showNotification(
            title: "⏱️ \(severity) Latency on \(device)",
            message: "Latency is \(String(format: "%.0f", latency))ms (threshold: \(String(format: "%.0f", threshold))ms)",
            identifier: identifier
        )
    }
    
    func notifyPacketLoss(device: String, packetLoss: Double) {
        guard packetLossNotifications else { return }
        
        let identifier = "packet-loss-\(device)"
        
        showNotification(
            title: "📉 Packet Loss Detected on \(device)",
            message: "Packet loss: \(String(format: "%.1f", packetLoss))%",
            identifier: identifier
        )
    }
    
    func notifyDailyReport(stats: DailyStats) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "📊 Daily Network Report"
        content.body = """
        Average Download: \(stats.avgDownloadFormatted)
        Average Upload: \(stats.avgUploadFormatted)
        Max Latency: \(stats.maxLatencyFormatted)
        Uptime: \(stats.uptimePercentageFormatted)
        """
        content.sound = nil // No sound for scheduled reports
        
        let request = UNNotificationRequest(
            identifier: "daily-report-\(Date().formatted(date: .numeric, time: .omitted))",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLogger.logError("Failed to send daily report notification", error: error)
            }
        }
    }
    
    // MARK: - Preference Management
    
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        if let enabled = defaults.object(forKey: "notificationsEnabled") as? Bool {
            notificationsEnabled = enabled
        }
        if let connLoss = defaults.object(forKey: "connectionLossNotifications") as? Bool {
            connectionLossNotifications = connLoss
        }
        if let highLat = defaults.object(forKey: "highLatencyNotifications") as? Bool {
            highLatencyNotifications = highLat
        }
        if let pktLoss = defaults.object(forKey: "packetLossNotifications") as? Bool {
            packetLossNotifications = pktLoss
        }
        if let connRest = defaults.object(forKey: "connectionRestoredNotifications") as? Bool {
            connectionRestoredNotifications = connRest
        }
        if let sound = defaults.object(forKey: "notificationSound") as? Bool {
            playSound = sound
        }
    }
    
    func savePreferences() {
        let defaults = UserDefaults.standard
        
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        defaults.set(connectionLossNotifications, forKey: "connectionLossNotifications")
        defaults.set(highLatencyNotifications, forKey: "highLatencyNotifications")
        defaults.set(packetLossNotifications, forKey: "packetLossNotifications")
        defaults.set(connectionRestoredNotifications, forKey: "connectionRestoredNotifications")
        defaults.set(playSound, forKey: "notificationSound")
    }
    
    // MARK: - Clear Notifications
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    func clearNotifications(for device: String) {
        let identifiers = [
            "connection-loss-\(device)",
            "connection-restored-\(device)",
            "latency-\(device)",
            "packet-loss-\(device)"
        ]
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
// MARK: - Supporting Types

struct DailyStats {
    let avgDownloadFormatted: String
    let avgUploadFormatted: String
    let maxLatencyFormatted: String
    let uptimePercentageFormatted: String
}
