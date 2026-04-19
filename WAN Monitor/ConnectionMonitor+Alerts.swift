//
//  ConnectionMonitor+Alerts.swift
//  WAN Monitor
//
//  Alert detection and management extension for ConnectionMonitor
//

import Foundation

extension ConnectionMonitor {
    /// Number of active alerts based on current network conditions
    var activeAlertCount: Int {
        var count = 0
        let config = NetworkConfiguration.shared
        
        // Check Device 1
        if device1ErrorMessage != nil {
            count += 1
        }
        if let latency = device1Latency, latency > config.device1LatencyWarningThreshold {
            count += 1
        }
        if device1PacketLoss > 5.0 {  // More than 5% packet loss
            count += 1
        }
        
        // Check Device 2 if enabled
        if config.device2Enabled {
            if device2ErrorMessage != nil {
                count += 1
            }
            if let latency = device2Latency, latency > config.device2LatencyWarningThreshold {
                count += 1
            }
            if device2PacketLoss > 5.0 {
                count += 1
            }
        }
        
        // Check LAN if enabled
        if config.lanEnabled {
            if lanErrorMessage != nil {
                count += 1
            }
        }
        
        return count
    }
    
    /// Get a list of current alert messages
    var activeAlerts: [NetworkAlert] {
        var alerts: [NetworkAlert] = []
        let config = NetworkConfiguration.shared
        
        // Device 1 alerts
        if let error = device1ErrorMessage {
            alerts.append(NetworkAlert(
                severity: .error,
                device: config.device1Label,
                message: error,
                timestamp: Date()
            ))
        }
        if let latency = device1Latency {
            if latency > config.device1LatencyCriticalThreshold {
                alerts.append(NetworkAlert(
                    severity: .critical,
                    device: config.device1Label,
                    message: "Critical latency: \(String(format: "%.1f", latency))ms",
                    timestamp: Date()
                ))
            } else if latency > config.device1LatencyWarningThreshold {
                alerts.append(NetworkAlert(
                    severity: .warning,
                    device: config.device1Label,
                    message: "High latency: \(String(format: "%.1f", latency))ms",
                    timestamp: Date()
                ))
            }
        }
        if device1PacketLoss > 10.0 {
            alerts.append(NetworkAlert(
                severity: .critical,
                device: config.device1Label,
                message: "High packet loss: \(String(format: "%.1f", device1PacketLoss))%",
                timestamp: Date()
            ))
        } else if device1PacketLoss > 5.0 {
            alerts.append(NetworkAlert(
                severity: .warning,
                device: config.device1Label,
                message: "Packet loss detected: \(String(format: "%.1f", device1PacketLoss))%",
                timestamp: Date()
            ))
        }
        
        // Device 2 alerts (if enabled)
        if config.device2Enabled {
            if let error = device2ErrorMessage {
                alerts.append(NetworkAlert(
                    severity: .error,
                    device: config.device2Label,
                    message: error,
                    timestamp: Date()
                ))
            }
            if let latency = device2Latency {
                if latency > config.device2LatencyCriticalThreshold {
                    alerts.append(NetworkAlert(
                        severity: .critical,
                        device: config.device2Label,
                        message: "Critical latency: \(String(format: "%.1f", latency))ms",
                        timestamp: Date()
                    ))
                } else if latency > config.device2LatencyWarningThreshold {
                    alerts.append(NetworkAlert(
                        severity: .warning,
                        device: config.device2Label,
                        message: "High latency: \(String(format: "%.1f", latency))ms",
                        timestamp: Date()
                    ))
                }
            }
            if device2PacketLoss > 10.0 {
                alerts.append(NetworkAlert(
                    severity: .critical,
                    device: config.device2Label,
                    message: "High packet loss: \(String(format: "%.1f", device2PacketLoss))%",
                    timestamp: Date()
                ))
            } else if device2PacketLoss > 5.0 {
                alerts.append(NetworkAlert(
                    severity: .warning,
                    device: config.device2Label,
                    message: "Packet loss detected: \(String(format: "%.1f", device2PacketLoss))%",
                    timestamp: Date()
                ))
            }
        }
        
        // LAN alerts (if enabled)
        if config.lanEnabled {
            if let error = lanErrorMessage {
                alerts.append(NetworkAlert(
                    severity: .error,
                    device: config.lanLabel,
                    message: error,
                    timestamp: Date()
                ))
            }
        }
        
        return alerts.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }
}

// MARK: - Network Alert Model

struct NetworkAlert: Identifiable {
    enum Severity: Int, Comparable {
        case info = 0
        case warning = 1
        case error = 2
        case critical = 3
        
        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
        
        var colorName: String {
            switch self {
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            case .critical: return "red"
            }
        }
    }
    
    let id = UUID()
    let severity: Severity
    let device: String
    let message: String
    let timestamp: Date
}
