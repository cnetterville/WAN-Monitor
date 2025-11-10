//
//  NotificationManager.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private var lastNotificationTime: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 300 // 5 minutes
    
    private init() {
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
    
    func notifyConnectionIssue(device: String, error: String) {
        let identifier = "connection-\(device)"
        
        // Check cooldown
        if let lastTime = lastNotificationTime[identifier],
           Date().timeIntervalSince(lastTime) < notificationCooldown {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "WAN Monitor Alert"
        content.body = "\(device) connection issue: \(error)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLogger.logError("Failed to send notification", error: error)
            } else {
                self.lastNotificationTime[identifier] = Date()
            }
        }
    }
    
    func notifyHighLatency(device: String, latency: Double) {
        let identifier = "latency-\(device)"
        
        // Check cooldown
        if let lastTime = lastNotificationTime[identifier],
           Date().timeIntervalSince(lastTime) < notificationCooldown {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "High Latency Detected"
        content.body = "\(device) latency is \(String(format: "%.0f", latency))ms"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLogger.logError("Failed to send notification", error: error)
            } else {
                self.lastNotificationTime[identifier] = Date()
            }
        }
    }
}