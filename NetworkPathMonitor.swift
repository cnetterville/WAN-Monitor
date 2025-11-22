//
//  NetworkPathMonitor.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import Network
import Combine

/// Monitors network path changes and notifies observers when network state changes
@MainActor
class NetworkPathMonitor: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isConnected: Bool = true
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var isExpensive: Bool = false
    @Published var isConstrained: Bool = false
    
    // MARK: - Private Properties
    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.wanmonitor.networkpathmonitor")
    
    // MARK: - Callbacks
    var onNetworkChange: ((NWPath) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }
    
    deinit {
        monitor.cancel()
        DebugLogger.logNetwork("NetworkPathMonitor stopped in deinit")
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                DebugLogger.logNetwork("Network path changed - Status: \(path.status)")
                
                // Update published properties
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                
                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                    DebugLogger.logNetwork("Connection type: WiFi")
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                    DebugLogger.logNetwork("Connection type: Cellular")
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wiredEthernet
                    DebugLogger.logNetwork("Connection type: Wired Ethernet")
                } else {
                    self.connectionType = nil
                    DebugLogger.logNetwork("Connection type: Unknown")
                }
                
                // Log additional details
                if path.status == .satisfied {
                    DebugLogger.logNetwork("Network is satisfied (connected)")
                } else if path.status == .unsatisfied {
                    DebugLogger.logNetwork("Network is unsatisfied (disconnected)")
                } else if path.status == .requiresConnection {
                    DebugLogger.logNetwork("Network requires connection")
                }
                
                if self.isExpensive {
                    DebugLogger.logNetwork("Network is expensive (cellular or hotspot)")
                }
                
                if self.isConstrained {
                    DebugLogger.logNetwork("Network is constrained (low data mode)")
                }
                
                // Notify callback
                self.onNetworkChange?(path)
            }
        }
        
        monitor.start(queue: monitorQueue)
        DebugLogger.logNetwork("NetworkPathMonitor started")
    }
    
    func stopMonitoring() {
        monitor.cancel()
        DebugLogger.logNetwork("NetworkPathMonitor stopped")
    }
    
    // MARK: - Helper Methods
    
    func getConnectionDescription() -> String {
        if !isConnected {
            return "No Connection"
        }
        
        var description = ""
        
        switch connectionType {
        case .wifi:
            description = "WiFi"
        case .cellular:
            description = "Cellular"
        case .wiredEthernet:
            description = "Ethernet"
        case .loopback:
            description = "Loopback"
        case .other:
            description = "Other"
        case .none:
            description = "Unknown"
        @unknown default:
            description = "Unknown"
        }
        
        if isExpensive {
            description += " (Expensive)"
        }
        
        if isConstrained {
            description += " (Low Data Mode)"
        }
        
        return description
    }
}
