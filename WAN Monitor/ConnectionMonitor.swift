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
            print("DEBUG: Device 1 interfaces being set to \(newValue.count) interfaces")
            if newValue.isEmpty && !_device1AvailableInterfaces.isEmpty {
                print("DEBUG: WARNING - Attempting to clear non-empty Device 1 interface list!")
                print("DEBUG: Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
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
            print("DEBUG: Device 2 interfaces being set to \(newValue.count) interfaces")
            if newValue.isEmpty && !_device2AvailableInterfaces.isEmpty {
                print("DEBUG: WARNING - Attempting to clear non-empty Device 2 interface list!")
                print("DEBUG: Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
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
    
    // MARK: - Monitoring State
    private var timer: Timer?
    private var latencyTimer: Timer?
    
    init(configuration: NetworkConfiguration? = nil) {
        // Use provided configuration or get shared instance on main actor
        if let config = configuration {
            self.configuration = config
        } else {
            self.configuration = NetworkConfiguration.shared
        }
        
        print("DEBUG: ConnectionMonitor init - Device 1: \(self.configuration.device1Host) (\(self.configuration.device1Label))")
        print("DEBUG: ConnectionMonitor init - Device 2: \(self.configuration.device2Host) (\(self.configuration.device2Label))")
        
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
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        print("DEBUG: Starting monitoring for both devices")
        
        // Reset device states
        device1Monitor.resetState()
        device2Monitor.resetState()
        
        resetUIState()
        
        // Start interface discovery for both devices before monitoring
        Task {
            print("DEBUG: Starting interface discovery for both devices")
            await discoverInterfaces(for: 1)
            await discoverInterfaces(for: 2)
            print("DEBUG: Interface discovery completed, starting traffic monitoring")
        }
        
        // Start monitoring timers with a delay to allow interface discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.startTrafficMonitoring()
            self.startLatencyMonitoring()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        latencyTimer?.invalidate()
        latencyTimer = nil
        resetUIState()
    }
    
    func discoverInterfaces(for deviceIndex: Int) async {
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        
        print("DEBUG: ===== STARTING INTERFACE DISCOVERY FOR DEVICE \(deviceIndex) =====")
        
        if deviceIndex == 1 {
            device1IsDiscoveringInterfaces = true
            device1ErrorMessage = nil
            // Don't clear interfaces immediately - keep the old ones until we have new ones
            print("DEBUG: Device 1 discovery started, current interface count: \(device1AvailableInterfaces.count)")
        } else {
            device2IsDiscoveringInterfaces = true
            device2ErrorMessage = nil
            print("DEBUG: Device 2 discovery started, current interface count: \(device2AvailableInterfaces.count)")
        }
        
        do {
            // Run interface discovery on background thread with proper isolation
            let interfaces = try await withCheckedThrowingContinuation { continuation in
                Task.detached { [monitor] in
                    do {
                        print("DEBUG: Starting background discovery task for device \(deviceIndex)")
                        let result = try await monitor.discoverInterfaces()
                        print("DEBUG: Background discovery completed for device \(deviceIndex), found \(result.count) interfaces")
                        continuation.resume(returning: result)
                    } catch {
                        print("DEBUG: Background discovery failed for device \(deviceIndex): \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            print("DEBUG: Discovery successful for device \(deviceIndex), updating UI with \(interfaces.count) interfaces")
            
            // Update UI on main actor
            if deviceIndex == 1 {
                self.device1AvailableInterfaces = interfaces
                self.device1IsDiscoveringInterfaces = false
                self.device1ErrorMessage = nil
                print("DEBUG: Device 1 interfaces updated: \(self.device1AvailableInterfaces.count) interfaces")
                print("DEBUG: Device 1 interface names: \(self.device1AvailableInterfaces.map { $0.name }.joined(separator: ", "))")
            } else {
                self.device2AvailableInterfaces = interfaces
                self.device2IsDiscoveringInterfaces = false
                self.device2ErrorMessage = nil
                print("DEBUG: Device 2 interfaces updated: \(self.device2AvailableInterfaces.count) interfaces")
                print("DEBUG: Device 2 interface names: \(self.device2AvailableInterfaces.map { $0.name }.joined(separator: ", "))")
            }
            
            // Add a delay and check if the interfaces are still there
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if deviceIndex == 1 {
                    print("DEBUG: 3 seconds later - Device 1 still has \(self.device1AvailableInterfaces.count) interfaces")
                } else {
                    print("DEBUG: 3 seconds later - Device 2 still has \(self.device2AvailableInterfaces.count) interfaces")
                }
            }
            
        } catch {
            print("DEBUG: Discovery failed for device \(deviceIndex): \(error)")
            if deviceIndex == 1 {
                self.device1ErrorMessage = error.localizedDescription
                self.device1IsDiscoveringInterfaces = false
                // Don't clear interfaces on error - keep the last successful discovery
                print("DEBUG: Device 1 discovery failed, keeping existing \(self.device1AvailableInterfaces.count) interfaces")
            } else {
                self.device2ErrorMessage = error.localizedDescription
                self.device2IsDiscoveringInterfaces = false
                print("DEBUG: Device 2 discovery failed, keeping existing \(self.device2AvailableInterfaces.count) interfaces")
            }
        }
        
        print("DEBUG: ===== DISCOVERY PROCESS COMPLETED FOR DEVICE \(deviceIndex) =====")
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
        print("DEBUG: ===== RESETTING UI STATE =====")
        print("DEBUG: Before reset - Device 1 interfaces: \(device1AvailableInterfaces.count)")
        print("DEBUG: Before reset - Device 2 interfaces: \(device2AvailableInterfaces.count)")
        
        device1UploadSpeed = 0.0
        device1DownloadSpeed = 0.0
        device1FormattedUploadSpeed = ("-", "-")
        device1FormattedDownloadSpeed = ("-", "-")
        device1Latency = nil
        device1FormattedLatency = "-"
        device1ErrorMessage = nil
        // Don't reset interfaces - they should persist until explicitly rediscovered
        // device1AvailableInterfaces = []
        
        device2UploadSpeed = 0.0
        device2DownloadSpeed = 0.0
        device2FormattedUploadSpeed = ("-", "-")
        device2FormattedDownloadSpeed = ("-", "-")
        device2Latency = nil
        device2FormattedLatency = "-"
        device2ErrorMessage = nil
        // Don't reset interfaces - they should persist until explicitly rediscovered  
        // device2AvailableInterfaces = []
        
        print("DEBUG: After reset - Device 1 interfaces: \(device1AvailableInterfaces.count)")
        print("DEBUG: After reset - Device 2 interfaces: \(device2AvailableInterfaces.count)")
        print("DEBUG: ===== UI STATE RESET COMPLETED =====")
    }
    
    private func startTrafficMonitoring() {
        // Increase the update interval to reduce SNMP pressure and avoid crashes
        let saferInterval = max(configuration.updateInterval, 5.0) // Minimum 5 seconds
        
        timer = Timer.scheduledTimer(withTimeInterval: saferInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateAllTrafficData()
            }
        }
    }
    
    private func startLatencyMonitoring() {
        latencyTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateAllLatency()
            }
        }
    }
    
    private func updateAllTrafficData() async {
        // Don't update both devices simultaneously to avoid SNMP race conditions
        await updateTrafficData(for: 1)
        
        // Add delay between device updates
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        await updateTrafficData(for: 2)
    }
    
    private func updateTrafficData(for deviceIndex: Int) async {
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        let availableInterfaces = deviceIndex == 1 ? device1AvailableInterfaces : device2AvailableInterfaces
        
        do {
            // Add circuit breaker logic - skip if too many consecutive failures
            let currentErrorMessage = deviceIndex == 1 ? device1ErrorMessage : device2ErrorMessage
            if let error = currentErrorMessage, error.contains("unreachable") {
                // Skip this update cycle if device was marked as unreachable recently
                return
            }
            
            // Run SNMP operations on background thread with proper isolation
            let (upload, download, formattedUpload, formattedDownload) = try await withCheckedThrowingContinuation { continuation in
                Task.detached { [monitor, availableInterfaces] in
                    do {
                        let result = try await monitor.updateTrafficData(availableInterfaces: availableInterfaces)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
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
            
            // If device is unreachable, reduce update frequency to prevent crashes
            if errorMessage.contains("unreachable") {
                print("DEBUG: Device \(deviceIndex) unreachable, will retry in next cycle")
            }
        }
    }
    
    private func updateAllLatency() async {
        let start = CFAbsoluteTimeGetCurrent()
        // Update both devices concurrently using a task group
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                await self.updateLatency(for: 1)
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.updateLatency(for: 2)
            }
            await group.waitForAll()
        }
        let duration = CFAbsoluteTimeGetCurrent() - start
        print("DEBUG: updateAllLatency completed in \(String(format: "%.3f", duration))s")
    }
    
    private func updateLatency(for deviceIndex: Int) async {
        let start = CFAbsoluteTimeGetCurrent()
        let monitor = deviceIndex == 1 ? device1Monitor : device2Monitor
        
        // Run latency check on background thread with proper isolation
        let (latency, formatted) = await withCheckedContinuation { continuation in
            Task.detached { [monitor] in
                let result = await monitor.updateLatency()
                continuation.resume(returning: result)
            }
        }
        
        // Update UI on main actor
        if deviceIndex == 1 {
            self.device1Latency = latency
            self.device1FormattedLatency = formatted
        } else {
            self.device2Latency = latency
            self.device2FormattedLatency = formatted
        }
        let duration = CFAbsoluteTimeGetCurrent() - start
        print("DEBUG: updateLatency(for: \(deviceIndex)) took \(String(format: "%.3f", duration))s")
    }
}

