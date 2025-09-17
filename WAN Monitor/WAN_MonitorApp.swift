//
//  WAN_MonitorApp.swift
//  WAN Monitor
//
//  Created by Curtis Netterville on 9/16/25.
//

import SwiftUI

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
        
        // Create status bar controller with delay to ensure app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.statusBarController = StatusBarController()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }
}