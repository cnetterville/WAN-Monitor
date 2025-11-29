//
//  Configuration.swift
//  WAN Monitor
//
//  Created by Curtis Netterville on 9/16/25.
//

import Foundation
import Combine
import ServiceManagement
import AppKit
import SwiftUI

enum SpeedDisplayUnit: String, CaseIterable {
    case bits = "bits"
    case bytes = "bytes"
    
    var displayName: String {
        switch self {
        case .bits: return "Bits per second (bps, Kbps, Mbps, Gbps)"
        case .bytes: return "Bytes per second (B/s, KB/s, MB/s, GB/s)"
        }
    }
}

@MainActor
class NetworkConfiguration: ObservableObject {
    static let shared = NetworkConfiguration()
    
    // Device 1 SNMP Settings
    @Published var device1Host = "192.168.86.1"
    @Published var device1Community = "public"
    @Published var device1Port = 161
    @Published var device1Label = "HW"
    @Published var device1InterfaceName = ""
    
    // Device 2 SNMP Settings
    @Published var device2Host = "192.168.87.1"
    @Published var device2Community = "public"
    @Published var device2Port = 161
    @Published var device2Label = "PW"
    @Published var device2InterfaceName = ""
    @Published var device2Enabled = true
    
    // Local LAN Interface Settings
    @Published var lanEnabled = false
    @Published var lanLabel = "LAN"
    @Published var lanInterfaceName = "en0"
    
    // Ping targets
    @Published var pingHost1 = "8.8.8.8"
    @Published var pingHost2 = "1.1.1.1"
    
    // Latency color coding thresholds (in milliseconds)
    @Published var device1LatencyColorEnabled = true
    @Published var device1LatencyWarningThreshold: Double = 50.0
    @Published var device1LatencyCriticalThreshold: Double = 100.0
    
    @Published var device2LatencyColorEnabled = true
    @Published var device2LatencyWarningThreshold: Double = 50.0
    @Published var device2LatencyCriticalThreshold: Double = 100.0
    
    // Update intervals
    @Published var updateInterval: TimeInterval = 1.0  // Changed from 2.0 to 1.0 for faster refresh
    @Published var pingInterval: TimeInterval = 5.0    // Changed from 6.0 to 5.0 for faster latency updates
    
    // Speed display preference
    @Published var speedDisplayUnit: SpeedDisplayUnit = .bits
    
    // Auto-start monitoring on app launch
    @Published var autoStartMonitoring: Bool = false
    
    // Start app at login
    @Published var startAtLogin: Bool = false {
        didSet {
            updateLoginItemStatus()
        }
    }
    
    // History settings
    @Published var historyRetentionMinutes: Int = 30 // How many minutes of history to keep in memory
    @Published var historySaveOnQuit: Bool = true // Whether to save history when quitting
    @Published var historyLoadOnStartup: Bool = true // Whether to load history on startup
    @Published var historyRetentionHoursOnStartup: Int = 24 // How many hours of old history to keep when loading
    
    private init() {
        // Load configuration synchronously to avoid race conditions
        loadConfiguration()
    }
    
    func saveConfiguration() {
        let defaults = UserDefaults.standard
        
        DebugLogger.logConfig("Saving configuration to UserDefaults")
        
        // Device 1
        defaults.set(device1Host, forKey: "device1Host")
        defaults.set(device1Community, forKey: "device1Community")
        defaults.set(device1Port, forKey: "device1Port")
        defaults.set(device1Label, forKey: "device1Label")
        defaults.set(device1InterfaceName, forKey: "device1InterfaceName")
        DebugLogger.logConfig("Saved Device 1 - Host: \(device1Host), Label: \(device1Label), Interface: '\(device1InterfaceName)'")
        
        // Device 2
        defaults.set(device2Host, forKey: "device2Host")
        defaults.set(device2Community, forKey: "device2Community")
        defaults.set(device2Port, forKey: "device2Port")
        defaults.set(device2Label, forKey: "device2Label")
        defaults.set(device2InterfaceName, forKey: "device2InterfaceName")
        defaults.set(device2Enabled, forKey: "device2Enabled")
        DebugLogger.logConfig("Saved Device 2 - Host: \(device2Host), Label: \(device2Label), Interface: '\(device2InterfaceName)', Enabled: \(device2Enabled)")
        
        // LAN Interface
        defaults.set(lanEnabled, forKey: "lanEnabled")
        defaults.set(lanLabel, forKey: "lanLabel")
        defaults.set(lanInterfaceName, forKey: "lanInterfaceName")
        DebugLogger.logConfig("Saved LAN - Label: \(lanLabel), Interface: '\(lanInterfaceName)', Enabled: \(lanEnabled)")
        
        // Ping hosts
        defaults.set(pingHost1, forKey: "pingHost1")
        defaults.set(pingHost2, forKey: "pingHost2")
        defaults.set(updateInterval, forKey: "updateInterval")
        defaults.set(pingInterval, forKey: "pingInterval")
        
        // Latency color thresholds
        defaults.set(device1LatencyColorEnabled, forKey: "device1LatencyColorEnabled")
        defaults.set(device1LatencyWarningThreshold, forKey: "device1LatencyWarningThreshold")
        defaults.set(device1LatencyCriticalThreshold, forKey: "device1LatencyCriticalThreshold")
        
        defaults.set(device2LatencyColorEnabled, forKey: "device2LatencyColorEnabled")
        defaults.set(device2LatencyWarningThreshold, forKey: "device2LatencyWarningThreshold")
        defaults.set(device2LatencyCriticalThreshold, forKey: "device2LatencyCriticalThreshold")
        
        // Speed display unit
        defaults.set(speedDisplayUnit.rawValue, forKey: "speedDisplayUnit")
        
        // Auto-start monitoring
        defaults.set(autoStartMonitoring, forKey: "autoStartMonitoring")
        
        // Start at login
        defaults.set(startAtLogin, forKey: "startAtLogin")
        
        // History settings
        defaults.set(historyRetentionMinutes, forKey: "historyRetentionMinutes")
        defaults.set(historySaveOnQuit, forKey: "historySaveOnQuit")
        defaults.set(historyLoadOnStartup, forKey: "historyLoadOnStartup")
        defaults.set(historyRetentionHoursOnStartup, forKey: "historyRetentionHoursOnStartup")
    }
    
    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        
        DebugLogger.logConfig("Loading configuration from UserDefaults")
        
        // Device 1 - Load with reduced logging
        if let host = defaults.object(forKey: "device1Host") as? String {
            device1Host = host
        } else if let oldHost = defaults.object(forKey: "snmpHost") as? String {
            device1Host = oldHost
            DebugLogger.logConfig("Migrated device1Host from old config: \(oldHost)")
        }
        
        if let community = defaults.object(forKey: "device1Community") as? String {
            device1Community = community
        } else if let oldCommunity = defaults.object(forKey: "snmpCommunity") as? String {
            device1Community = oldCommunity
            DebugLogger.logConfig("Migrated device1Community from old config")
        }
        
        if defaults.object(forKey: "device1Port") != nil {
            device1Port = defaults.integer(forKey: "device1Port")
        } else if defaults.object(forKey: "snmpPort") != nil {
            device1Port = defaults.integer(forKey: "snmpPort")
            DebugLogger.logConfig("Migrated device1Port from old config: \(device1Port)")
        }
        
        if let label = defaults.object(forKey: "device1Label") as? String {
            device1Label = label
        } else if let oldLabel = defaults.object(forKey: "interface1Label") as? String {
            device1Label = oldLabel
            DebugLogger.logConfig("Migrated device1Label from old config: \(oldLabel)")
        }
        
        if let interfaceName = defaults.object(forKey: "device1InterfaceName") as? String {
            device1InterfaceName = interfaceName
        }
        
        // Device 2 - Load with reduced logging
        if let host = defaults.object(forKey: "device2Host") as? String {
            device2Host = host
        }
        
        if let community = defaults.object(forKey: "device2Community") as? String {
            device2Community = community
        }
        
        if defaults.object(forKey: "device2Port") != nil {
            device2Port = defaults.integer(forKey: "device2Port")
        }
        
        if let label = defaults.object(forKey: "device2Label") as? String {
            device2Label = label
        } else if let oldLabel = defaults.object(forKey: "interface2Label") as? String {
            device2Label = oldLabel
            DebugLogger.logConfig("Migrated device2Label from old config: \(oldLabel)")
        }
        
        if let interfaceName = defaults.object(forKey: "device2InterfaceName") as? String {
            device2InterfaceName = interfaceName
        }
        
        // Device 2 enabled state - defaults to true for existing configurations
        if defaults.object(forKey: "device2Enabled") != nil {
            device2Enabled = defaults.bool(forKey: "device2Enabled")
        }
        
        // LAN Interface
        if defaults.object(forKey: "lanEnabled") != nil {
            lanEnabled = defaults.bool(forKey: "lanEnabled")
        }
        
        if let label = defaults.object(forKey: "lanLabel") as? String {
            lanLabel = label
        }
        
        if let interfaceName = defaults.object(forKey: "lanInterfaceName") as? String {
            lanInterfaceName = interfaceName
        }
        
        // Ping hosts and other settings
        if let ping1 = defaults.object(forKey: "pingHost1") as? String {
            pingHost1 = ping1
        }
        
        if let ping2 = defaults.object(forKey: "pingHost2") as? String {
            pingHost2 = ping2
        }
        
        if defaults.object(forKey: "updateInterval") != nil {
            updateInterval = defaults.double(forKey: "updateInterval")
        }
        
        if defaults.object(forKey: "pingInterval") != nil {
            pingInterval = defaults.double(forKey: "pingInterval")
        }
        
        // Latency color thresholds
        if defaults.object(forKey: "device1LatencyColorEnabled") != nil {
            device1LatencyColorEnabled = defaults.bool(forKey: "device1LatencyColorEnabled")
        }
        if defaults.object(forKey: "device1LatencyWarningThreshold") != nil {
            device1LatencyWarningThreshold = defaults.double(forKey: "device1LatencyWarningThreshold")
        }
        if defaults.object(forKey: "device1LatencyCriticalThreshold") != nil {
            device1LatencyCriticalThreshold = defaults.double(forKey: "device1LatencyCriticalThreshold")
        }
        
        if defaults.object(forKey: "device2LatencyColorEnabled") != nil {
            device2LatencyColorEnabled = defaults.bool(forKey: "device2LatencyColorEnabled")
        }
        if defaults.object(forKey: "device2LatencyWarningThreshold") != nil {
            device2LatencyWarningThreshold = defaults.double(forKey: "device2LatencyWarningThreshold")
        }
        if defaults.object(forKey: "device2LatencyCriticalThreshold") != nil {
            device2LatencyCriticalThreshold = defaults.double(forKey: "device2LatencyCriticalThreshold")
        }
        
        if let speedUnitString = defaults.object(forKey: "speedDisplayUnit") as? String,
           let speedUnit = SpeedDisplayUnit(rawValue: speedUnitString) {
            speedDisplayUnit = speedUnit
        }
        
        // Auto-start monitoring - defaults to false for opt-in behavior
        if defaults.object(forKey: "autoStartMonitoring") != nil {
            autoStartMonitoring = defaults.bool(forKey: "autoStartMonitoring")
        }
        
        // Start at login - defaults to false for opt-in behavior
        if defaults.object(forKey: "startAtLogin") != nil {
            startAtLogin = defaults.bool(forKey: "startAtLogin")
        }
        
        // History settings
        if defaults.object(forKey: "historyRetentionMinutes") != nil {
            historyRetentionMinutes = defaults.integer(forKey: "historyRetentionMinutes")
        }
        if defaults.object(forKey: "historySaveOnQuit") != nil {
            historySaveOnQuit = defaults.bool(forKey: "historySaveOnQuit")
        }
        if defaults.object(forKey: "historyLoadOnStartup") != nil {
            historyLoadOnStartup = defaults.bool(forKey: "historyLoadOnStartup")
        }
        if defaults.object(forKey: "historyRetentionHoursOnStartup") != nil {
            historyRetentionHoursOnStartup = defaults.integer(forKey: "historyRetentionHoursOnStartup")
        }
        
        // Sync with actual login item status on startup
        syncLoginItemStatus()
        
        DebugLogger.logConfig("Configuration loading completed")
        DebugLogger.logConfig("Final config - Device 1: \(device1Host) (\(device1Label)), Device 2: \(device2Host) (\(device2Label)) [Enabled: \(device2Enabled)]")
    }
    
    // MARK: - Login Item Management
    
    private func updateLoginItemStatus() {
        do {
            try LoginItemManager.shared.setLoginItemEnabled(startAtLogin)
            DebugLogger.logConfig("Login item status updated: \(startAtLogin)")
        } catch {
            DebugLogger.logError("Failed to update login item status", error: error)
        }
    }
    
    private func syncLoginItemStatus() {
        let actualStatus = LoginItemManager.shared.isLoginItemEnabled
        if actualStatus != startAtLogin {
            DebugLogger.logConfig("Syncing login item status from system: \(actualStatus)")
            startAtLogin = actualStatus
        }
    }
    
    // MARK: - Validation Methods
    
    func validateDevice1Configuration() -> [String] {
        var errors: [String] = []
        
        if device1Host.isEmpty {
            errors.append("Device 1 IP address is required")
        } else if !isValidIPAddress(device1Host) {
            errors.append("Device 1 IP address format is invalid")
        }
        
        if device1Community.isEmpty {
            errors.append("Device 1 SNMP community string is required")
        }
        
        if device1Port < 1 || device1Port > 65535 {
            errors.append("Device 1 SNMP port must be between 1 and 65535")
        }
        
        if device1Label.isEmpty {
            errors.append("Device 1 label is required")
        }
        
        return errors
    }
    
    func validateDevice2Configuration() -> [String] {
        guard device2Enabled else { return [] }
        
        var errors: [String] = []
        
        if device2Host.isEmpty {
            errors.append("Device 2 IP address is required")
        } else if !isValidIPAddress(device2Host) {
            errors.append("Device 2 IP address format is invalid")
        }
        
        if device2Community.isEmpty {
            errors.append("Device 2 SNMP community string is required")
        }
        
        if device2Port < 1 || device2Port > 65535 {
            errors.append("Device 2 SNMP port must be between 1 and 65535")
        }
        
        if device2Label.isEmpty {
            errors.append("Device 2 label is required")
        }
        
        return errors
    }
    
    private func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        
        for part in parts {
            guard let num = Int(part), num >= 0 && num <= 255 else {
                return false
            }
        }
        return true
    }
    
    func getAllValidationErrors() -> [String] {
        return validateDevice1Configuration() + validateDevice2Configuration()
    }
    
    // MARK: - Latency Color Helpers
    
    func getLatencyColor(for deviceIndex: Int, latency: Double) -> NSColor? {
        let colorEnabled = deviceIndex == 1 ? device1LatencyColorEnabled : device2LatencyColorEnabled
        
        guard colorEnabled else { return nil }
        
        let warningThreshold = deviceIndex == 1 ? device1LatencyWarningThreshold : device2LatencyWarningThreshold
        let criticalThreshold = deviceIndex == 1 ? device1LatencyCriticalThreshold : device2LatencyCriticalThreshold
        
        if latency >= criticalThreshold {
            return .systemRed
        } else if latency >= warningThreshold {
            return .systemOrange
        } else {
            return .white
        }
    }
    
    func getLatencyColorSwiftUI(for deviceIndex: Int, latency: Double) -> Color? {
        let colorEnabled = deviceIndex == 1 ? device1LatencyColorEnabled : device2LatencyColorEnabled
        
        guard colorEnabled else { return nil }
        
        let warningThreshold = deviceIndex == 1 ? device1LatencyWarningThreshold : device2LatencyWarningThreshold
        let criticalThreshold = deviceIndex == 1 ? device1LatencyCriticalThreshold : device2LatencyCriticalThreshold
        
        if latency >= criticalThreshold {
            return Color(NSColor.systemRed)
        } else if latency >= warningThreshold {
            return Color(NSColor.systemOrange)
        } else {
            return .white
        }
    }
}