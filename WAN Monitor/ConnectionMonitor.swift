//
//  ConnectionMonitor.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import SwiftSnmpKit
import Combine

@MainActor
class ConnectionMonitor: ObservableObject {
    
    // MARK: - Published Properties for Device 1
    @Published var device1UploadSpeed: Double = 0.0
    @Published var device1DownloadSpeed: Double = 0.0
    @Published var device1FormattedUploadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var device1FormattedDownloadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var device1Latency: Double? = nil
    @Published var device1FormattedLatency: String = "-"
    @Published var device1ErrorMessage: String?
    @Published private var _device1AvailableInterfaces: [NetworkInterface] = []
    @Published var device1IsDiscoveringInterfaces = false
    
    // Computed property to prevent accidental clearing of interfaces
    var device1AvailableInterfaces: [NetworkInterface] {
        get { _device1AvailableInterfaces }
        set { 
            DebugLogger.logUI("Device 1 interfaces being set to \(newValue.count) interfaces")
            if newValue.isEmpty && !_device1AvailableInterfaces.isEmpty {
                DebugLogger.logError("WARNING - Attempting to clear non-empty Device 1 interface list!")
            }
            _device1AvailableInterfaces = newValue 
        }
    }
    
    // MARK: - Published Properties for Device 2
    @Published var device2UploadSpeed: Double = 0.0
    @Published var device2DownloadSpeed: Double = 0.0
    @Published var device2FormattedUploadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var device2FormattedDownloadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var device2Latency: Double? = nil
    @Published var device2FormattedLatency: String = "-"
    @Published var device2ErrorMessage: String?
    @Published private var _device2AvailableInterfaces: [NetworkInterface] = []
    @Published var device2IsDiscoveringInterfaces = false
    
    // Computed property to prevent accidental clearing of interfaces
    var device2AvailableInterfaces: [NetworkInterface] {
        get { _device2AvailableInterfaces }
        set { 
            DebugLogger.logUI("Device 2 interfaces being set to \(newValue.count) interfaces")
            if newValue.isEmpty && !_device2AvailableInterfaces.isEmpty {
                DebugLogger.logError("WARNING - Attempting to clear non-empty Device 2 interface list!")
            }
            _device2AvailableInterfaces = newValue 
        }
    }
    
    // MARK: - General State
    @Published var isMonitoring = false
    
    // MARK: - Configuration
    private let configuration: NetworkConfiguration
    
    // MARK: - Device Monitors
    private var device1Monitor: DeviceMonitor
    private var device2Monitor: DeviceMonitor
    
    // MARK: - Consolidated Timer Management
    private var consolidatedTimer: Timer?
    private var monitoringCycle: Int = 0
    private let trafficUpdateCycles = 1 // Update traffic every cycle
    private var latencyUpdateCycles: Int {
        // Calculate how many cycles to skip based on ping interval and update interval
        let cycles = Int(configuration.pingInterval / configuration.updateInterval)
        return max(1, cycles) // At least 1 cycle
    }
    
    // MARK: - Task Management
    private var activeDiscoveryTasks: [UUID] = []
    private var activeMonitoringTasks: [UUID] = []
    
    init(configuration: NetworkConfiguration? = nil) {
        // Use provided configuration or get shared instance on main actor
        if let config = configuration {
            self.configuration = config
        } else {
            self.configuration = NetworkConfiguration.shared
        }
        
        DebugLogger.logConfig("ConnectionMonitor init - Device 1: \(self.configuration.device1Host) (\(self.configuration.device1Label))")
        DebugLogger.logConfig("ConnectionMonitor init - Device 2: \(self.configuration.device2Host) (\(self.configuration.device2Label))")
        
        // Create device monitors with current configuration values
        self.device1Monitor = DeviceMonitor(
            deviceIndex: 1,
            host: self.configuration.device1Host,
            community: self.configuration.device1Community,
            port: self.configuration.device1Port,
            label: self.configuration.device1Label,
            interfaceName: self.configuration.device1InterfaceName,
            pingHost: self.configuration.pingHost1
        )
        
        self.device2Monitor = DeviceMonitor(
            deviceIndex: 2,
            host: self.configuration.device2Host,
            community: self.configuration.device2Community,
            port: self.configuration.device2Port,
            label: self.configuration.device2Label,
            interfaceName: self.configuration.device2InterfaceName,
            pingHost: self.configuration.pingHost2
        )
        
        // Observe configuration changes and recreate monitors
        setupConfigurationObserver()
    }
    
    deinit {
        DebugLogger.logConfig("ConnectionMonitor deinit - cleaning up resources")
        consolidatedTimer?.invalidate()
        
        // Cancel tasks asynchronously since we can't await in deinit
        let discoveryTasks = activeDiscoveryTasks
        let monitoringTasks = activeMonitoringTasks
        
        Task { @MainActor in
            for taskId in discoveryTasks {
                await SNMPManager.shared.cancelTask(taskId: taskId)
            }
            for taskId in monitoringTasks {
                await SNMPManager.shared.cancelTask(taskId: taskId)
            }
        }
        
        cancellables.removeAll()
    }

    // MARK: - Configuration Observer
    
    private func setupConfigurationObserver() {
        configuration.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDeviceMonitors()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func updateDeviceMonitors() {
        let wasMonitoring = isMonitoring
        
        // Check if monitors actually need to be recreated
        let needsDevice1Update = device1Monitor.host != configuration.device1Host ||
                                  device1Monitor.community != configuration.device1Community ||
                                  device1Monitor.port != configuration.device1Port ||
                                  device1Monitor.interfaceName != configuration.device1InterfaceName ||
                                  device1Monitor.pingHost != configuration.pingHost1
        
        let needsDevice2Update = device2Monitor.host != configuration.device2Host ||
                                  device2Monitor.community != configuration.device2Community ||
                                  device2Monitor.port != configuration.device2Port ||
                                  device2Monitor.interfaceName != configuration.device2InterfaceName ||
                                  device2Monitor.pingHost != configuration.pingHost2
        
        // Only update if something actually changed
        guard needsDevice1Update || needsDevice2Update else {
            DebugLogger.logConfig("Configuration changed but monitors don't need recreation")
            return
        }
        
        // Stop monitoring if active
        if wasMonitoring {
            stopMonitoring()
        }
        
        // Cancel active tasks
        cancelAllActiveTasks()
        
        // Recreate device monitors with new configuration
        device1Monitor = DeviceMonitor(
            deviceIndex: 1,
            host: configuration.device1Host,
            community: configuration.device1Community,
            port: configuration.device1Port,
            label: configuration.device1Label,
            interfaceName: configuration.device1InterfaceName,
            pingHost: configuration.pingHost1
        )
        
        device2Monitor = DeviceMonitor(
            deviceIndex: 2,
            host: configuration.device2Host,
            community: configuration.device2Community,
            port: configuration.device2Port,
            label: configuration.device2Label,
            interfaceName: configuration.device2InterfaceName,
            pingHost: configuration.pingHost2
        )
        
        // Restart monitoring if it was active
        if wasMonitoring {
            Task { @MainActor in
                self.startMonitoring()
            }
        }
    }
    
    // MARK: - Task Management
    
    private func cancelAllActiveTasks() {
        // Cancel discovery tasks
        for taskId in activeDiscoveryTasks {
            Task {
                await SNMPManager.shared.cancelTask(taskId: taskId)
            }
        }
        activeDiscoveryTasks.removeAll()
        
        // Cancel monitoring tasks
        for taskId in activeMonitoringTasks {
            Task {
                await SNMPManager.shared.cancelTask(taskId: taskId)
            }
        }
        activeMonitoringTasks.removeAll()
    }
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitoringCycle = 0
        
        DebugLogger.logNetwork("Starting monitoring for devices (Device 2 enabled: \(configuration.device2Enabled))")
        
        // Reset device states
        device1Monitor.resetState()
        if configuration.device2Enabled {
            device2Monitor.resetState()
        }
        
        resetUIState()
        
        // Start interface discovery for enabled devices before monitoring
        Task {
            DebugLogger.logNetwork("Starting interface discovery for enabled devices")
            await discoverInterfaces(for: 1)
            if configuration.device2Enabled {
                await discoverInterfaces(for: 2)
            }
            DebugLogger.logNetwork("Interface discovery completed, starting consolidated monitoring")
        }
        
        // Start consolidated monitoring timer with a delay to allow interface discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.startConsolidatedMonitoring()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        
        // Stop consolidated timer
        consolidatedTimer?.invalidate()
        consolidatedTimer = nil
        
        // Cancel all active tasks
        cancelAllActiveTasks()
        
        resetUIState()
    }
    
    func discoverInterfaces(for deviceIndex: Int) async {
        // Skip device 2 if it's disabled
        if deviceIndex == 2 && !configuration.device2Enabled {
            DebugLogger.logNetwork("Skipping interface discovery for Device 2 - disabled")
            return
        }
        
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        let taskId = UUID()
        activeDiscoveryTasks.append(taskId)
        
        DebugLogger.logNetwork("===== STARTING INTERFACE DISCOVERY FOR DEVICE \(deviceIndex) =====")
        
        if deviceIndex == 1 {
            device1IsDiscoveringInterfaces = true
            device1ErrorMessage = nil
            DebugLogger.logUI("Device 1 discovery started, current interface count: \(device1AvailableInterfaces.count)")
        } else {
            device2IsDiscoveringInterfaces = true
            device2ErrorMessage = nil
            DebugLogger.logUI("Device 2 discovery started, current interface count: \(device2AvailableInterfaces.count)")
        }
        
        do {
            // Use the centralized SNMP manager and pass update interval
            let interfaces = try await monitor.discoverInterfaces(using: SNMPManager.shared, updateInterval: configuration.updateInterval, taskId: taskId)
            
            DebugLogger.logNetwork("Discovery successful for device \(deviceIndex), updating UI with \(interfaces.count) interfaces")
            
            // Update UI on main actor
            if deviceIndex == 1 {
                self.device1AvailableInterfaces = interfaces
                self.device1IsDiscoveringInterfaces = false
                self.device1ErrorMessage = nil
                DebugLogger.logUI("Device 1 interfaces updated: \(self.device1AvailableInterfaces.count) interfaces")
            } else if configuration.device2Enabled {
                self.device2AvailableInterfaces = interfaces
                self.device2IsDiscoveringInterfaces = false
                self.device2ErrorMessage = nil
                DebugLogger.logUI("Device 2 interfaces updated: \(self.device2AvailableInterfaces.count) interfaces")
            }
            
        } catch {
            DebugLogger.logError("Discovery failed for device \(deviceIndex)", error: error)
            if deviceIndex == 1 {
                self.device1ErrorMessage = error.localizedDescription
                self.device1IsDiscoveringInterfaces = false
            } else if configuration.device2Enabled {
                self.device2ErrorMessage = error.localizedDescription
                self.device2IsDiscoveringInterfaces = false
            }
        }
        
        // Remove task from active list
        if let index = activeDiscoveryTasks.firstIndex(of: taskId) {
            activeDiscoveryTasks.remove(at: index)
        }
        
        DebugLogger.logNetwork("===== DISCOVERY PROCESS COMPLETED FOR DEVICE \(deviceIndex) =====")
    }
    
    // MARK: - Convenience Properties for Backwards Compatibility
    
    var uploadSpeed: Double {
        return device1UploadSpeed
    }
    
    var downloadSpeed: Double {
        return device1DownloadSpeed
    }
    
    var formattedUploadSpeed: (value: String, unit: String) {
        return device1FormattedUploadSpeed
    }
    
    var formattedDownloadSpeed: (value: String, unit: String) {
        return device1FormattedDownloadSpeed
    }
    
    var latency: Double? {
        return device1Latency
    }
    
    var formattedLatency: String {
        return device1FormattedLatency
    }
    
    var errorMessage: String? {
        return device1ErrorMessage ?? device2ErrorMessage
    }
    
    var availableInterfaces: [NetworkInterface] {
        return device1AvailableInterfaces
    }
    
    var isDiscoveringInterfaces: Bool {
        return device1IsDiscoveringInterfaces || device2IsDiscoveringInterfaces
    }
    
    // MARK: - Private Methods
    
    private func resetUIState() {
        DebugLogger.logUI("===== RESETTING UI STATE =====")
        
        device1UploadSpeed = 0.0
        device1DownloadSpeed = 0.0
        device1FormattedUploadSpeed = ("-", "-")
        device1FormattedDownloadSpeed = ("-", "-")
        device1Latency = nil
        device1FormattedLatency = "-"
        device1ErrorMessage = nil
        
        device2UploadSpeed = 0.0
        device2DownloadSpeed = 0.0
        device2FormattedUploadSpeed = ("-", "-")
        device2FormattedDownloadSpeed = ("-", "-")
        device2Latency = nil
        device2FormattedLatency = "-"
        device2ErrorMessage = nil
        
        DebugLogger.logUI("===== UI STATE RESET COMPLETED =====")
    }
    
    // MARK: - Resilient Consolidated Monitoring
    
    private func startConsolidatedMonitoring() {
        // Use user's update interval directly - no artificial minimum
        let saferInterval = configuration.updateInterval
        
        DebugLogger.logNetwork("Starting consolidated monitoring with interval: \(saferInterval)s")
        
        consolidatedTimer = Timer.scheduledTimer(withTimeInterval: saferInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Simply call the monitoring update - errors are handled within the method
                await self.performConsolidatedUpdate()
            }
        }
    }
    
    private func performConsolidatedUpdate() async {
        guard isMonitoring else { return }
        
        monitoringCycle += 1
        
        #if DEBUG
        DebugLogger.logNetwork("=== Consolidated monitoring cycle \(monitoringCycle) ===")
        #endif
        
        // Always update traffic data with error handling
        if monitoringCycle % trafficUpdateCycles == 0 {
            await updateAllTrafficDataWithRetry()
        }
        
        // Update latency based on user-configured ping interval
        if monitoringCycle % latencyUpdateCycles == 0 {
            await updateAllLatencyWithRetry()
        }
        
        // Periodic interface rediscovery for failed devices
        if monitoringCycle % 20 == 0 { // Every 20 cycles, check for interface rediscovery
            await performPeriodicInterfaceRediscovery()
        }
    }
    
    private func updateAllTrafficDataWithRetry() async {
        // Update both devices concurrently if device 2 is enabled
        if configuration.device2Enabled {
            // Create task IDs on main actor
            let taskId1 = UUID()
            let taskId2 = UUID()
            addActiveMonitoringTask(taskId1)
            addActiveMonitoringTask(taskId2)
            
            // Run updates concurrently
            async let update1: Void = updateTrafficDataWithRetry(for: 1, taskId: taskId1)
            async let update2: Void = updateTrafficDataWithRetry(for: 2, taskId: taskId2)
            
            _ = await (update1, update2)
            
            // Cleanup on main actor
            cleanupTasks([taskId1, taskId2])
        } else {
            // Only update device 1
            let taskId1 = UUID()
            addActiveMonitoringTask(taskId1)
            await updateTrafficDataWithRetry(for: 1, taskId: taskId1)
            cleanupTasks([taskId1])
        }
    }
    
    private func addActiveMonitoringTask(_ taskId: UUID) {
        activeMonitoringTasks.append(taskId)
    }
    
    private func updateTrafficDataWithRetry(for deviceIndex: Int, taskId: UUID) async {
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        let availableInterfaces = deviceIndex == 1 ? device1AvailableInterfaces : device2AvailableInterfaces
        
        do {
            // Use centralized SNMP manager with proper task management
            let (upload, download, formattedUpload, formattedDownload) = try await monitor.updateTrafficData(
                availableInterfaces: availableInterfaces, 
                using: SNMPManager.shared,
                updateInterval: configuration.updateInterval,
                taskId: taskId
            )
            
            // Update UI on main actor
            if deviceIndex == 1 {
                self.device1UploadSpeed = upload
                self.device1DownloadSpeed = download
                self.device1FormattedUploadSpeed = formattedUpload
                self.device1FormattedDownloadSpeed = formattedDownload
                self.device1ErrorMessage = nil
                
                // Add to history
                HistoryManager.shared.addDataPoint(
                    device: 1,
                    uploadSpeed: upload,
                    downloadSpeed: download,
                    latency: self.device1Latency
                )
            } else {
                self.device2UploadSpeed = upload
                self.device2DownloadSpeed = download
                self.device2FormattedUploadSpeed = formattedUpload
                self.device2FormattedDownloadSpeed = formattedDownload
                self.device2ErrorMessage = nil
                
                // Add to history
                HistoryManager.shared.addDataPoint(
                    device: 2,
                    uploadSpeed: upload,
                    downloadSpeed: download,
                    latency: self.device2Latency
                )
            }
            
        } catch NetworkDiscoveryError.interfaceNotFound {
            // Interface rediscovery needed
            DebugLogger.logNetwork("Device \(deviceIndex) - Interface not found, triggering rediscovery")
            Task {
                await self.discoverInterfaces(for: deviceIndex)
            }
            
            let errorMessage = "Interface discovery needed"
            if deviceIndex == 1 {
                self.device1ErrorMessage = errorMessage
            } else {
                self.device2ErrorMessage = errorMessage
            }
            
        } catch NetworkDiscoveryError.deviceUnreachable {
            // Circuit breaker is open, show appropriate message
            let errorMessage = "Device temporarily unreachable (backing off)"
            if deviceIndex == 1 {
                self.device1ErrorMessage = errorMessage
            } else {
                self.device2ErrorMessage = errorMessage
            }
            
        } catch {
            let errorMessage = error.localizedDescription
            if deviceIndex == 1 {
                self.device1ErrorMessage = errorMessage
            } else {
                self.device2ErrorMessage = errorMessage
            }
            
            DebugLogger.logError("Device \(deviceIndex) traffic update failed", error: error)
        }
    }
    
    private func updateAllLatencyWithRetry() async {
        // Update both devices concurrently but with proper error handling
        let taskId1 = UUID()
        activeMonitoringTasks.append(taskId1)
        
        if configuration.device2Enabled {
            let taskId2 = UUID()
            activeMonitoringTasks.append(taskId2)
            
            // Update devices concurrently with individual error handling
            async let latency1: Void = updateLatencyWithRetry(for: 1, taskId: taskId1)
            async let latency2: Void = updateLatencyWithRetry(for: 2, taskId: taskId2)
            
            _ = await (latency1, latency2)
            
            // Remove tasks from active list
            cleanupTasks([taskId1, taskId2])
        } else {
            // Only update device 1
            await updateLatencyWithRetry(for: 1, taskId: taskId1)
            cleanupTasks([taskId1])
        }
    }
    
    private func updateLatencyWithRetry(for deviceIndex: Int, taskId: UUID) async {
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        
        let (latency, formatted) = await monitor.updateLatency(taskId: taskId)
        
        // Update UI on main actor
        if deviceIndex == 1 {
            self.device1Latency = latency
            self.device1FormattedLatency = formatted
        } else {
            self.device2Latency = latency
            self.device2FormattedLatency = formatted
        }
    }
    
    private func performPeriodicInterfaceRediscovery() async {
        // Check if any devices need interface rediscovery based on error states
        let device1NeedsRediscovery = device1ErrorMessage?.contains("Interface") ?? false ||
                                     device1ErrorMessage?.contains("not found") ?? false ||
                                     device1AvailableInterfaces.isEmpty
        
        if device1NeedsRediscovery {
            DebugLogger.logNetwork("Periodic rediscovery triggered for Device 1")
            await discoverInterfaces(for: 1)
        }
        
        // Only check device 2 if it's enabled
        if configuration.device2Enabled {
            let device2NeedsRediscovery = device2ErrorMessage?.contains("Interface") ?? false ||
                                         device2ErrorMessage?.contains("not found") ?? false ||
                                         device2AvailableInterfaces.isEmpty
            
            if device2NeedsRediscovery {
                DebugLogger.logNetwork("Periodic rediscovery triggered for Device 2")
                await discoverInterfaces(for: 2)
            }
        }
    }
    
    private func cleanupTasks(_ taskIds: [UUID]) {
        for taskId in taskIds {
            if let index = activeMonitoringTasks.firstIndex(of: taskId) {
                activeMonitoringTasks.remove(at: index)
            }
        }
    }
}