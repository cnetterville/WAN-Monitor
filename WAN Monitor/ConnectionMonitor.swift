//
//  ConnectionMonitor.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import SwiftSnmpKit
import Combine
import Network

@MainActor
class ConnectionMonitor: ObservableObject {
    
    // MARK: - Published Properties for Device 1
    @Published var device1UploadSpeed: Double = 0.0
    @Published var device1DownloadSpeed: Double = 0.0
    @Published var device1FormattedUploadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var device1FormattedDownloadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var device1Latency: Double? = nil
    @Published var device1FormattedLatency: String = "-"
    @Published var device1PacketsSent: Int = 0
    @Published var device1PacketsReceived: Int = 0
    @Published var device1PacketLoss: Double = 0.0
    @Published var device1FormattedPacketLoss: String = "-"
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
    @Published var device2PacketsSent: Int = 0
    @Published var device2PacketsReceived: Int = 0
    @Published var device2PacketLoss: Double = 0.0
    @Published var device2FormattedPacketLoss: String = "-"
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
    
    // MARK: - Published Properties for LAN
    @Published var lanUploadSpeed: Double = 0.0
    @Published var lanDownloadSpeed: Double = 0.0
    @Published var lanFormattedUploadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var lanFormattedDownloadSpeed: (value: String, unit: String) = ("-", "-")
    @Published var lanErrorMessage: String?
    @Published var lanAvailableInterfaces: [LocalInterface] = []
    @Published var lanIsDiscoveringInterfaces = false
    
    // MARK: - General State
    @Published var isMonitoring = false
    
    // MARK: - Configuration
    private let configuration: NetworkConfiguration
    
    // MARK: - Network Path Monitoring
    private var networkPathMonitor: NetworkPathMonitor?
    
    // MARK: - Device Monitors
    private var device1Monitor: DeviceMonitor
    private var device2Monitor: DeviceMonitor
    private var lanMonitor: LocalInterfaceMonitor?
    
    // MARK: - Consolidated Monitoring Management
    private var monitoringTask: Task<Void, Never>?
    private var monitoringCycle: Int = 0
    private let trafficUpdateCycles = 1 // Update traffic every cycle
    private var latencyUpdateCycles: Int {
        // Calculate how many cycles to skip based on ping interval and update interval
        let cycles = Int(configuration.pingInterval / configuration.updateInterval)
        return max(1, cycles) // At least 1 cycle
    }
    private var historyUpdateCycles: Int {
        // Add to history every 30 seconds (or at least every 3 cycles)
        let cycles = Int(30.0 / configuration.updateInterval)
        return max(3, cycles) // At least 3 cycles between history updates
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
        
        // Create LAN monitor if enabled
        if self.configuration.lanEnabled {
            self.lanMonitor = LocalInterfaceMonitor(
                interfaceName: self.configuration.lanInterfaceName,
                label: self.configuration.lanLabel
            )
        }
        
        // Setup network path monitoring
        setupNetworkPathMonitoring()
        
        // Observe configuration changes and recreate monitors
        setupConfigurationObserver()
    }
    
    deinit {
        DebugLogger.logConfig("ConnectionMonitor deinit - cleaning up resources")
        
        // Cancel monitoring task
        monitoringTask?.cancel()
        
        // Stop network path monitoring - call cancel directly to avoid main actor isolation
        networkPathMonitor = nil
        
        // Cancel tasks asynchronously since we can't await in deinit
        let discoveryTasks = activeDiscoveryTasks
        let monitoringTasks = activeMonitoringTasks
        
        // Use unstructured task for cleanup in deinit
        Task.detached {
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
    
    // MARK: - Network Path Monitoring
    
    private func setupNetworkPathMonitoring() {
        networkPathMonitor = NetworkPathMonitor()
        
        // Handle network path changes
        networkPathMonitor?.onNetworkChange = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                DebugLogger.logNetwork("Network path change detected in ConnectionMonitor")
                
                // If monitoring is active, handle the network change
                if self.isMonitoring {
                    if path.status == .satisfied {
                        DebugLogger.logNetwork("Network connected - ensuring monitoring continues")
                        // Network is back - trigger interface rediscovery to ensure we're monitoring correctly
                        Task {
                            await self.handleNetworkReconnection()
                        }
                    } else {
                        DebugLogger.logNetwork("Network disconnected - monitoring will continue with errors")
                        // Network is down - monitoring will continue but likely show errors
                        // Circuit breakers will handle the failures gracefully
                    }
                }
            }
        }
    }
    
    private func handleNetworkReconnection() async {
        DebugLogger.logNetwork("Handling network reconnection - rediscovering interfaces")
        
        // Reset device states to clear any stale data
        device1Monitor.resetState()
        if configuration.device2Enabled {
            device2Monitor.resetState()
        }
        if configuration.lanEnabled {
            lanMonitor?.resetState()
        }
        
        // Rediscover interfaces for all enabled devices
        await discoverInterfaces(for: 1)
        if configuration.device2Enabled {
            await discoverInterfaces(for: 2)
        }
        if configuration.lanEnabled {
            await discoverLANInterfaces()
        }
        
        DebugLogger.logNetwork("Network reconnection handling completed")
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
        
        let needsLANUpdate = (configuration.lanEnabled && lanMonitor == nil) ||
                            (!configuration.lanEnabled && lanMonitor != nil) ||
                            (lanMonitor?.interfaceName != configuration.lanInterfaceName) ||
                            (lanMonitor?.label != configuration.lanLabel)
        
        // Only update if something actually changed
        guard needsDevice1Update || needsDevice2Update || needsLANUpdate else {
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
        
        // Recreate LAN monitor if enabled
        if configuration.lanEnabled {
            lanMonitor = LocalInterfaceMonitor(
                interfaceName: configuration.lanInterfaceName,
                label: configuration.lanLabel
            )
        } else {
            lanMonitor = nil
        }
        
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
        
        DebugLogger.logNetwork("Starting monitoring for devices (Device 2 enabled: \(configuration.device2Enabled), LAN enabled: \(configuration.lanEnabled))")
        
        // Reset device states
        device1Monitor.resetState()
        if configuration.device2Enabled {
            device2Monitor.resetState()
        }
        if configuration.lanEnabled {
            lanMonitor?.resetState()
        }
        
        resetUIState()
        
        // Start interface discovery for enabled devices before monitoring
        Task {
            DebugLogger.logNetwork("Starting interface discovery for enabled devices")
            await discoverInterfaces(for: 1)
            if configuration.device2Enabled {
                await discoverInterfaces(for: 2)
            }
            if configuration.lanEnabled {
                await discoverLANInterfaces()
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
        
        // Cancel monitoring task
        monitoringTask?.cancel()
        monitoringTask = nil
        
        // Cancel all active tasks
        cancelAllActiveTasks()
        
        resetUIState()
        
        DebugLogger.logNetwork("Monitoring stopped")
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
    
    func discoverLANInterfaces() async {
        guard configuration.lanEnabled else {
            DebugLogger.logNetwork("Skipping LAN interface discovery - disabled")
            return
        }
        
        DebugLogger.logNetwork("===== STARTING LAN INTERFACE DISCOVERY =====")
        
        lanIsDiscoveringInterfaces = true
        lanErrorMessage = nil
        
        // Discover local interfaces
        let interfaces = LocalInterfaceMonitor.discoverLocalInterfaces()
        
        DebugLogger.logNetwork("Discovery successful for LAN, found \(interfaces.count) interfaces")
        
        self.lanAvailableInterfaces = interfaces
        self.lanIsDiscoveringInterfaces = false
        self.lanErrorMessage = nil
        
        DebugLogger.logNetwork("===== LAN DISCOVERY PROCESS COMPLETED =====")
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
        device1PacketsSent = 0
        device1PacketsReceived = 0
        device1PacketLoss = 0.0
        device1FormattedPacketLoss = "-"
        device1ErrorMessage = nil
        
        device2UploadSpeed = 0.0
        device2DownloadSpeed = 0.0
        device2FormattedUploadSpeed = ("-", "-")
        device2FormattedDownloadSpeed = ("-", "-")
        device2Latency = nil
        device2FormattedLatency = "-"
        device2PacketsSent = 0
        device2PacketsReceived = 0
        device2PacketLoss = 0.0
        device2FormattedPacketLoss = "-"
        device2ErrorMessage = nil
        
        lanUploadSpeed = 0.0
        lanDownloadSpeed = 0.0
        lanFormattedUploadSpeed = ("-", "-")
        lanFormattedDownloadSpeed = ("-", "-")
        lanErrorMessage = nil
        
        DebugLogger.logUI("===== UI STATE RESET COMPLETED =====")
    }
    
    // MARK: - Resilient Consolidated Monitoring with Modern Swift Concurrency
    
    private func startConsolidatedMonitoring() {
        // Cancel any existing monitoring task
        monitoringTask?.cancel()
        
        let updateInterval = configuration.updateInterval
        
        DebugLogger.logNetwork("Starting consolidated monitoring with interval: \(updateInterval)s")
        
        // Create a new monitoring task using structured concurrency
        monitoringTask = Task { @MainActor in
            while !Task.isCancelled && isMonitoring {
                await performConsolidatedUpdate()
                
                // Sleep for the update interval
                do {
                    try await Task.sleep(for: .seconds(updateInterval))
                } catch {
                    // Task was cancelled
                    break
                }
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
        // Update all devices concurrently
        if configuration.device2Enabled && configuration.lanEnabled {
            // All three enabled
            let taskId1 = UUID()
            let taskId2 = UUID()
            let taskId3 = UUID()
            addActiveMonitoringTask(taskId1)
            addActiveMonitoringTask(taskId2)
            addActiveMonitoringTask(taskId3)
            
            async let update1: Void = updateTrafficDataWithRetry(for: 1, taskId: taskId1)
            async let update2: Void = updateTrafficDataWithRetry(for: 2, taskId: taskId2)
            async let update3: Void = updateLANTrafficDataWithRetry(taskId: taskId3)
            
            _ = await (update1, update2, update3)
            cleanupTasks([taskId1, taskId2, taskId3])
            
        } else if configuration.device2Enabled {
            // Device 1 and 2 enabled, LAN disabled
            let taskId1 = UUID()
            let taskId2 = UUID()
            addActiveMonitoringTask(taskId1)
            addActiveMonitoringTask(taskId2)
            
            async let update1: Void = updateTrafficDataWithRetry(for: 1, taskId: taskId1)
            async let update2: Void = updateTrafficDataWithRetry(for: 2, taskId: taskId2)
            
            _ = await (update1, update2)
            cleanupTasks([taskId1, taskId2])
            
        } else if configuration.lanEnabled {
            // Device 1 and LAN enabled, Device 2 disabled
            let taskId1 = UUID()
            let taskId2 = UUID()
            addActiveMonitoringTask(taskId1)
            addActiveMonitoringTask(taskId2)
            
            async let update1: Void = updateTrafficDataWithRetry(for: 1, taskId: taskId1)
            async let update2: Void = updateLANTrafficDataWithRetry(taskId: taskId2)
            
            _ = await (update1, update2)
            cleanupTasks([taskId1, taskId2])
            
        } else {
            // Only device 1 enabled
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
                
                // Add to history only on history update cycles to avoid overwhelming the system
                if self.monitoringCycle % self.historyUpdateCycles == 0 {
                    HistoryManager.shared.addDataPoint(
                        device: 1,
                        uploadSpeed: upload,
                        downloadSpeed: download,
                        latency: self.device1Latency,
                        packetLoss: self.device1PacketLoss
                    )
                }
            } else {
                self.device2UploadSpeed = upload
                self.device2DownloadSpeed = download
                self.device2FormattedUploadSpeed = formattedUpload
                self.device2FormattedDownloadSpeed = formattedDownload
                self.device2ErrorMessage = nil
                
                // Add to history only on history update cycles to avoid overwhelming the system
                if self.monitoringCycle % self.historyUpdateCycles == 0 {
                    HistoryManager.shared.addDataPoint(
                        device: 2,
                        uploadSpeed: upload,
                        downloadSpeed: download,
                        latency: self.device2Latency,
                        packetLoss: self.device2PacketLoss
                    )
                }
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
    
    private func updateLANTrafficDataWithRetry(taskId: UUID) async {
        guard let lanMonitor = lanMonitor else {
            lanErrorMessage = "LAN monitor not initialized"
            return
        }
        
        do {
            let (upload, download, formattedUpload, formattedDownload) = try await lanMonitor.updateTrafficData()
            
            // Update UI on main actor
            self.lanUploadSpeed = upload
            self.lanDownloadSpeed = download
            self.lanFormattedUploadSpeed = formattedUpload
            self.lanFormattedDownloadSpeed = formattedDownload
            self.lanErrorMessage = nil
            
            // Add to history only on history update cycles
            if self.monitoringCycle % self.historyUpdateCycles == 0 {
                HistoryManager.shared.addDataPoint(
                    device: 3, // Use device 3 for LAN
                    uploadSpeed: upload,
                    downloadSpeed: download,
                    latency: nil,
                    packetLoss: nil
                )
            }
            
        } catch NetworkDiscoveryError.interfaceNotFound {
            // Interface not found - could be temporarily down, keep showing last values
            DebugLogger.logNetwork("LAN - Interface temporarily unavailable, keeping last values")
            
            // Don't clear the current values - just set a subtle error
            // This prevents the "---" display when interface is temporarily down
            self.lanErrorMessage = "Interface temporarily unavailable"
            
            // Try rediscovery after a few failures
            if self.monitoringCycle % 5 == 0 {
                DebugLogger.logNetwork("LAN - Attempting interface rediscovery")
                Task {
                    await self.discoverLANInterfaces()
                }
            }
            
        } catch {
            let errorMessage = error.localizedDescription
            DebugLogger.logError("LAN traffic update failed", error: error)
            
            // Keep last values instead of clearing them
            self.lanErrorMessage = errorMessage
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
        
        let (latency, formatted, packetsSent, packetsReceived, packetLoss, formattedLoss) = await monitor.updateLatency(taskId: taskId)
        
        // Update UI on main actor
        if deviceIndex == 1 {
            self.device1Latency = latency
            self.device1FormattedLatency = formatted
            self.device1PacketsSent = packetsSent
            self.device1PacketsReceived = packetsReceived
            self.device1PacketLoss = packetLoss
            self.device1FormattedPacketLoss = formattedLoss
        } else {
            self.device2Latency = latency
            self.device2FormattedLatency = formatted
            self.device2PacketsSent = packetsSent
            self.device2PacketsReceived = packetsReceived
            self.device2PacketLoss = packetLoss
            self.device2FormattedPacketLoss = formattedLoss
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