//
//  LoginItemManager.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import ServiceManagement
import AppKit

class LoginItemManager {
    static let shared = LoginItemManager()
    
    private init() {}
    
    // MARK: - Login Item Management
    
    /// Check if the app is currently set to start at login
    var isLoginItemEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS versions using deprecated API
            return isLoginItemEnabledLegacy()
        }
    }
    
    /// Enable or disable the app starting at login
    func setLoginItemEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } else {
            // Fallback for older macOS versions
            try setLoginItemEnabledLegacy(enabled)
        }
    }
    
    // MARK: - Legacy Support (macOS < 13.0)
    
    @available(macOS, deprecated: 13.0)
    private func isLoginItemEnabledLegacy() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)
        guard let loginItemsRef = loginItems?.takeRetainedValue() else { return false }
        
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItemsRef, nil)
        guard let snapshot = loginItemsSnapshot?.takeRetainedValue() as? Array<LSSharedFileListItem> else {
            return false
        }
        
        for loginItem in snapshot {
            let itemURL = LSSharedFileListItemCopyResolvedURL(loginItem, 0, nil)
            if let url = itemURL?.takeRetainedValue() as URL? {
                if let itemBundle = Bundle(url: url),
                   itemBundle.bundleIdentifier == bundleId {
                    return true
                }
            }
        }
        
        return false
    }
    
    @available(macOS, deprecated: 13.0)
    private func setLoginItemEnabledLegacy(_ enabled: Bool) throws {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw LoginItemError.bundleInfoNotAvailable
        }
        
        let appURL = Bundle.main.bundleURL
        
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)
        guard let loginItemsRef = loginItems?.takeRetainedValue() else {
            throw LoginItemError.cannotAccessLoginItems
        }
        
        if enabled {
            // Add to login items
            LSSharedFileListInsertItemURL(
                loginItemsRef,
                kLSSharedFileListItemLast.takeRetainedValue(),
                nil,
                nil,
                appURL as CFURL,
                nil,
                nil
            )
        } else {
            // Remove from login items
            let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItemsRef, nil)
            guard let snapshot = loginItemsSnapshot?.takeRetainedValue() as? Array<LSSharedFileListItem> else {
                return
            }
            
            for loginItem in snapshot {
                let itemURL = LSSharedFileListItemCopyResolvedURL(loginItem, 0, nil)
                if let url = itemURL?.takeRetainedValue() as URL? {
                    if let itemBundle = Bundle(url: url),
                       itemBundle.bundleIdentifier == bundleId {
                        LSSharedFileListItemRemove(loginItemsRef, loginItem)
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Error Types

enum LoginItemError: LocalizedError {
    case bundleInfoNotAvailable
    case cannotAccessLoginItems
    case registrationFailed
    
    var errorDescription: String? {
        switch self {
        case .bundleInfoNotAvailable:
            return "Cannot access app bundle information"
        case .cannotAccessLoginItems:
            return "Cannot access login items list"
        case .registrationFailed:
            return "Failed to register/unregister login item"
        }
    }
}