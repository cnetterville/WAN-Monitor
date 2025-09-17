//
//  DebugLogger.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation

struct DebugLogger {
    // Compile-time debug flag - set to false for production
    private static let isDebugEnabled = true
    
    nonisolated static func log(_ message: String, category: String = "DEBUG") {
        #if DEBUG
        if isDebugEnabled {
            print("[\(category)] \(message)")
        }
        #endif
    }
    
    nonisolated static func logError(_ message: String, error: Error? = nil) {
        #if DEBUG
        if let error = error {
            print("[ERROR] \(message): \(error)")
        } else {
            print("[ERROR] \(message)")
        }
        #else
        // In production, only log errors to console
        if let error = error {
            NSLog("[WAN Monitor ERROR] \(message): \(error)")
        } else {
            NSLog("[WAN Monitor ERROR] \(message)")
        }
        #endif
    }
    
    nonisolated static func logSNMP(_ message: String) {
        log(message, category: "SNMP")
    }
    
    nonisolated static func logUI(_ message: String) {
        log(message, category: "UI")
    }
    
    nonisolated static func logConfig(_ message: String) {
        log(message, category: "CONFIG")
    }
    
    nonisolated static func logNetwork(_ message: String) {
        log(message, category: "NETWORK")
    }
}