//
//  Configuration.swift
//  WAN Monitor
//
//  Created by Curtis Netterville on 9/16/25.
//

import Foundation
import Combine

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
    
    // Ping targets
    @Published var pingHost1 = "8.8.8.8"
    @Published var pingHost2 = "1.1.1.1"
    
    // Update intervals
    @Published var updateInterval: TimeInterval = 2.0
    
    // Speed display preference
    @Published var speedDisplayUnit: SpeedDisplayUnit = .bits
    
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
        DebugLogger.logConfig("Saved Device 2 - Host: \(device2Host), Label: \(device2Label), Interface: '\(device2InterfaceName)'")
        
        // Ping hosts
        defaults.set(pingHost1, forKey: "pingHost1")
        defaults.set(pingHost2, forKey: "pingHost2")
        defaults.set(updateInterval, forKey: "updateInterval")
        
        // Speed display unit
        defaults.set(speedDisplayUnit.rawValue, forKey: "speedDisplayUnit")
        
        DebugLogger.logConfig("Configuration saved - Device 1: \(device1Host) (\(device1Label)), Device 2: \(device2Host) (\(device2Label))")
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
        
        if let speedUnitString = defaults.object(forKey: "speedDisplayUnit") as? String,
           let speedUnit = SpeedDisplayUnit(rawValue: speedUnitString) {
            speedDisplayUnit = speedUnit
        }
        
        DebugLogger.logConfig("Configuration loading completed")
        DebugLogger.logConfig("Final config - Device 1: \(device1Host) (\(device1Label)), Device 2: \(device2Host) (\(device2Label))")
    }
}