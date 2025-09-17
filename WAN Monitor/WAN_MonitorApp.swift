//
//  WAN_MonitorApp.swift
//  WAN Monitor
//
//  Created by Curtis Netterville on 9/16/25.
//

import SwiftUI
import SwiftSnmpKit

@main
struct WAN_MonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize SNMP service early
        initializeSNMP()
        
        // Create status bar controller with delay to ensure app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.statusBarController = StatusBarController()
        }
    }
    
    private func initializeSNMP() {
        print("DEBUG: Initializing SNMP service...")
        
        // Try to access SNMP sender to trigger initialization
        DispatchQueue.global(qos: .background).async {
            for attempt in 1...10 {
                if let snmp = SnmpSender.shared {
                    print("DEBUG: SNMP initialized successfully on attempt \(attempt)")
                    return
                } else {
                    print("DEBUG: SNMP initialization attempt \(attempt) failed, retrying...")
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            print("ERROR: Failed to initialize SNMP after all attempts")
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }
}