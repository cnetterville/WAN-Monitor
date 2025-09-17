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
    private let latencyUpdateCycles = 3 // Update latency every 3 cycles (less frequently)
    
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
        
        DebugLogger.logNetwork("Starting monitoring for both devices")
        
        // Reset device states
        device1Monitor.resetState()
        device2Monitor.resetState()
        
        resetUIState()
        
        // Start interface discovery for both devices before monitoring
        Task {
            DebugLogger.logNetwork("Starting interface discovery for both devices")
            await discoverInterfaces(for: 1)
            await discoverInterfaces(for: 2)
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
            // Use the centralized SNMP manager instead of direct Task.detached
            let interfaces = try await monitor.discoverInterfaces(using: SNMPManager.shared, taskId: taskId)
            
            DebugLogger.logNetwork("Discovery successful for device \(deviceIndex), updating UI with \(interfaces.count) interfaces")
            
            // Update UI on main actor
            if deviceIndex == 1 {
                self.device1AvailableInterfaces = interfaces
                self.device1IsDiscoveringInterfaces = false
                self.device1ErrorMessage = nil
                DebugLogger.logUI("Device 1 interfaces updated: \(self.device1AvailableInterfaces.count) interfaces")
            } else {
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
            } else {
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
    
    // MARK: - Consolidated Monitoring
    
    private func startConsolidatedMonitoring() {
        // Use a safer interval and consolidate all monitoring into one timer
        let saferInterval = max(configuration.updateInterval, 5.0) // Minimum 5 seconds
        
        consolidatedTimer = Timer.scheduledTimer(withTimeInterval: saferInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performConsolidatedUpdate()
            }
        }
    }
    
    private func performConsolidatedUpdate() async {
        guard isMonitoring else { return }
        
        monitoringCycle += 1
        DebugLogger.logNetwork("=== Consolidated monitoring cycle \(monitoringCycle) ===")
        
        // Always update traffic data
        if monitoringCycle % trafficUpdateCycles == 0 {
            await updateAllTrafficData()
        }
        
        // Update latency less frequently to reduce load
        if monitoringCycle % latencyUpdateCycles == 0 {
            await updateAllLatency()
        }
    }
    
    private func updateAllTrafficData() async {
        // Stagger device updates to avoid overwhelming the network devices
        let taskId1 = UUID()
        let taskId2 = UUID()
        
        activeMonitoringTasks.append(contentsOf: [taskId1, taskId2])
        
        // Update device 1 first
        await updateTrafficData(for: 1, taskId: taskId1)
        
        // Add delay between device updates
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        } catch {
            // Task was cancelled, clean up and return
            if let index1 = activeMonitoringTasks.firstIndex(of: taskId1) {
                activeMonitoringTasks.remove(at: index1)
            }
            if let index2 = activeMonitoringTasks.firstIndex(of: taskId2) {
                activeMonitoringTasks.remove(at: index2)
            }
            return
        }
        
        // Update device 2
        await updateTrafficData(for: 2, taskId: taskId2)
        
        // Remove tasks from active list
        if let index1 = activeMonitoringTasks.firstIndex(of: taskId1) {
            activeMonitoringTasks.remove(at: index1)
        }
        if let index2 = activeMonitoringTasks.firstIndex(of: taskId2) {
            activeMonitoringTasks.remove(at: index2)
        }
    }
    
    private func updateTrafficData(for deviceIndex: Int, taskId: UUID) async {
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        let availableInterfaces = deviceIndex == 1 ? device1AvailableInterfaces : device2AvailableInterfaces
        
        do {
            // Add circuit breaker logic - skip if too many consecutive failures
            let currentErrorMessage = deviceIndex == 1 ? device1ErrorMessage : device2ErrorMessage
            if let error = currentErrorMessage, error.contains("unreachable") {
                DebugLogger.logNetwork("Device \(deviceIndex) - Skipping update due to unreachable status")
                return
            }
            
            // Use centralized SNMP manager with proper task management
            let (upload, download, formattedUpload, formattedDownload) = try await monitor.updateTrafficData(
                availableInterfaces: availableInterfaces, 
                using: SNMPManager.shared, 
                taskId: taskId
            )
            
            // Update UI on main actor
            if deviceIndex == 1 {
                self.device1UploadSpeed = upload
                self.device1DownloadSpeed = download
                self.device1FormattedUploadSpeed = formattedUpload
                self.device1FormattedDownloadSpeed = formattedDownload
                self.device1ErrorMessage = nil
            } else {
                self.device2UploadSpeed = upload
                self.device2DownloadSpeed = download
                self.device2FormattedUploadSpeed = formattedUpload
                self.device2FormattedDownloadSpeed = formattedDownload
                self.device2ErrorMessage = nil
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
    
    private func updateAllLatency() async {
        // Update both devices concurrently but with proper task management
        let taskId1 = UUID()
        let taskId2 = UUID()
        
        activeMonitoringTasks.append(contentsOf: [taskId1, taskId2])
        
        async let device1Update = updateLatency(for: 1, taskId: taskId1)
        async let device2Update = updateLatency(for: 2, taskId: taskId2)
        
        let _ = await (device1Update, device2Update)
        
        // Remove tasks from active list
        if let index1 = activeMonitoringTasks.firstIndex(of: taskId1) {
            activeMonitoringTasks.remove(at: index1)
        }
        if let index2 = activeMonitoringTasks.firstIndex(of: taskId2) {
            activeMonitoringTasks.remove(at: index2)
        }
    }
    
    private func updateLatency(for deviceIndex: Int, taskId: UUID) async {
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
}