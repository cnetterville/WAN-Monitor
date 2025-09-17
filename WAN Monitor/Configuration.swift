//
//  Configuration.swift
//  WAN Monitor
//
//  Created by Curtis Netterville on 9/16/25.
//

import Foundation
import Combine

class NetworkConfiguration: ObservableObject {
    static let shared = NetworkConfiguration()
    
    // SNMP Settings
    @Published var snmpHost = "192.168.1.1"
    @Published var snmpCommunity = "public"
    @Published var snmpPort = 161
    
    // Interface Labels
    @Published var interface1Label = "HW"
    @Published var interface2Label = "PW"
    
    // Ping targets
    @Published var pingHost1 = "8.8.8.8"
    @Published var pingHost2 = "1.1.1.1"
    
    // Update intervals
    let updateInterval: TimeInterval = 2.0
    
    private init() {
        loadConfiguration()
    }
    
    func saveConfiguration() {
        let defaults = UserDefaults.standard
        defaults.set(snmpHost, forKey: "snmpHost")
        defaults.set(snmpCommunity, forKey: "snmpCommunity")
        defaults.set(snmpPort, forKey: "snmpPort")
        defaults.set(interface1Label, forKey: "interface1Label")
        defaults.set(interface2Label, forKey: "interface2Label")
        defaults.set(pingHost1, forKey: "pingHost1")
        defaults.set(pingHost2, forKey: "pingHost2")
        print("Configuration saved!")
    }
    
    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        
        if let host = defaults.object(forKey: "snmpHost") as? String {
            snmpHost = host
        }
        if let community = defaults.object(forKey: "snmpCommunity") as? String {
            snmpCommunity = community
        }
        if defaults.object(forKey: "snmpPort") != nil {
            snmpPort = defaults.integer(forKey: "snmpPort")
        }
        if let label1 = defaults.object(forKey: "interface1Label") as? String {
            interface1Label = label1
        }
        if let label2 = defaults.object(forKey: "interface2Label") as? String {
            interface2Label = label2
        }
        if let ping1 = defaults.object(forKey: "pingHost1") as? String {
            pingHost1 = ping1
        }
        if let ping2 = defaults.object(forKey: "pingHost2") as? String {
            pingHost2 = ping2
        }
    }
}