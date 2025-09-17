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
    
    nonisolated private init() {
        // Load configuration synchronously to avoid race conditions
        loadConfiguration()
    }
    
    func saveConfiguration() {
        let defaults = UserDefaults.standard
        
        print("DEBUG: Saving configuration to UserDefaults")
        
        // Device 1
        defaults.set(device1Host, forKey: "device1Host")
        defaults.set(device1Community, forKey: "device1Community")
        defaults.set(device1Port, forKey: "device1Port")
        defaults.set(device1Label, forKey: "device1Label")
        defaults.set(device1InterfaceName, forKey: "device1InterfaceName")
        print("DEBUG: Saved Device 1 - Host: \(device1Host), Label: \(device1Label), Interface: '\(device1InterfaceName)'")
        
        // Device 2
        defaults.set(device2Host, forKey: "device2Host")
        defaults.set(device2Community, forKey: "device2Community")
        defaults.set(device2Port, forKey: "device2Port")
        defaults.set(device2Label, forKey: "device2Label")
        defaults.set(device2InterfaceName, forKey: "device2InterfaceName")
        print("DEBUG: Saved Device 2 - Host: \(device2Host), Label: \(device2Label), Interface: '\(device2InterfaceName)'")
        
        // Ping hosts
        defaults.set(pingHost1, forKey: "pingHost1")
        defaults.set(pingHost2, forKey: "pingHost2")
        defaults.set(updateInterval, forKey: "updateInterval")
        
        // Speed display unit
        defaults.set(speedDisplayUnit.rawValue, forKey: "speedDisplayUnit")
        
        print("DEBUG: Configuration saved - Device 1: \(device1Host) (\(device1Label)), Device 2: \(device2Host) (\(device2Label))")
    }
    
    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        
        print("DEBUG: Loading configuration from UserDefaults")
        
        // Device 1
        if let host = defaults.object(forKey: "device1Host") as? String {
            device1Host = host
            print("DEBUG: Loaded device1Host: \(host)")
        } else if let oldHost = defaults.object(forKey: "snmpHost") as? String {
            // Migration from old config
            device1Host = oldHost
            print("DEBUG: Migrated device1Host from old config: \(oldHost)")
        } else {
            print("DEBUG: Using default device1Host: \(device1Host)")
        }
        
        if let community = defaults.object(forKey: "device1Community") as? String {
            device1Community = community
            print("DEBUG: Loaded device1Community: \(community)")
        } else if let oldCommunity = defaults.object(forKey: "snmpCommunity") as? String {
            device1Community = oldCommunity
            print("DEBUG: Migrated device1Community from old config: \(oldCommunity)")
        } else {
            print("DEBUG: Using default device1Community: \(device1Community)")
        }
        
        if defaults.object(forKey: "device1Port") != nil {
            device1Port = defaults.integer(forKey: "device1Port")
            print("DEBUG: Loaded device1Port: \(device1Port)")
        } else if defaults.object(forKey: "snmpPort") != nil {
            device1Port = defaults.integer(forKey: "snmpPort")
            print("DEBUG: Migrated device1Port from old config: \(device1Port)")
        } else {
            print("DEBUG: Using default device1Port: \(device1Port)")
        }
        
        if let label = defaults.object(forKey: "device1Label") as? String {
            device1Label = label
            print("DEBUG: Loaded device1Label: \(label)")
        } else if let oldLabel = defaults.object(forKey: "interface1Label") as? String {
            device1Label = oldLabel
            print("DEBUG: Migrated device1Label from old config: \(oldLabel)")
        } else {
            print("DEBUG: Using default device1Label: \(device1Label)")
        }
        
        if let interfaceName = defaults.object(forKey: "device1InterfaceName") as? String {
            device1InterfaceName = interfaceName
            print("DEBUG: Loaded device1InterfaceName: \(interfaceName)")
        } else {
            print("DEBUG: Using default device1InterfaceName: \(device1InterfaceName)")
        }
        
        // Device 2
        print("DEBUG: Loading Device 2 configuration...")
        if let host = defaults.object(forKey: "device2Host") as? String {
            device2Host = host
            print("DEBUG: Loaded device2Host: \(host)")
        } else {
            print("DEBUG: Using default device2Host: \(device2Host)")
        }
        
        if let community = defaults.object(forKey: "device2Community") as? String {
            device2Community = community
            print("DEBUG: Loaded device2Community: \(community)")
        } else {
            print("DEBUG: Using default device2Community: \(device2Community)")
        }
        
        if defaults.object(forKey: "device2Port") != nil {
            device2Port = defaults.integer(forKey: "device2Port")
            print("DEBUG: Loaded device2Port: \(device2Port)")
        } else {
            print("DEBUG: Using default device2Port: \(device2Port)")
        }
        
        if let label = defaults.object(forKey: "device2Label") as? String {
            device2Label = label
            print("DEBUG: Loaded device2Label: \(label)")
        } else if let oldLabel = defaults.object(forKey: "interface2Label") as? String {
            device2Label = oldLabel
            print("DEBUG: Migrated device2Label from old config: \(oldLabel)")
        } else {
            print("DEBUG: Using default device2Label: \(device2Label)")
        }
        
        if let interfaceName = defaults.object(forKey: "device2InterfaceName") as? String {
            device2InterfaceName = interfaceName
            print("DEBUG: Loaded device2InterfaceName: \(interfaceName)")
        } else {
            print("DEBUG: Using default device2InterfaceName: \(device2InterfaceName)")
        }
        
        // Ping hosts
        if let ping1 = defaults.object(forKey: "pingHost1") as? String {
            pingHost1 = ping1
            print("DEBUG: Loaded pingHost1: \(ping1)")
        } else {
            print("DEBUG: Using default pingHost1: \(pingHost1)")
        }
        
        if let ping2 = defaults.object(forKey: "pingHost2") as? String {
            pingHost2 = ping2
            print("DEBUG: Loaded pingHost2: \(ping2)")
        } else {
            print("DEBUG: Using default pingHost2: \(pingHost2)")
        }
        
        if defaults.object(forKey: "updateInterval") != nil {
            updateInterval = defaults.double(forKey: "updateInterval")
            print("DEBUG: Loaded updateInterval: \(updateInterval)")
        } else {
            print("DEBUG: Using default updateInterval: \(updateInterval)")
        }
        
        // Speed display unit
        if let speedUnitString = defaults.object(forKey: "speedDisplayUnit") as? String,
           let speedUnit = SpeedDisplayUnit(rawValue: speedUnitString) {
            speedDisplayUnit = speedUnit
            print("DEBUG: Loaded speedDisplayUnit: \(speedUnit.rawValue)")
        } else {
            print("DEBUG: Using default speedDisplayUnit: \(speedDisplayUnit.rawValue)")
        }
        
        print("DEBUG: Configuration loading completed")
        print("DEBUG: Final config - Device 1: \(device1Host) (\(device1Label)), Device 2: \(device2Host) (\(device2Label))")
    }
}