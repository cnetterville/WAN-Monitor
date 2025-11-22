import AppKit
import SwiftUI
import Combine

class StatusBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: ConnectionMonitor
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var device1HistoryWindow: NSWindow?
    private var device2HistoryWindow: NSWindow?
    
    // MARK: - Hosted SwiftUI View
    private var hostingView: NSHostingView<StatusBarView>?
    private var lastUpdateTime = Date.distantPast
    private let minUpdateInterval: TimeInterval = 0.1

    override init() {
        self.monitor = ConnectionMonitor()
        super.init()
        setupStatusItem()
        setupMonitorObservers()
        
        // Wait longer for configuration to load, then start monitoring only if auto-start is enabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let config = NetworkConfiguration.shared
            DebugLogger.logUI("StatusBarController - Configuration loaded, auto-start: \(config.autoStartMonitoring)")
            DebugLogger.logConfig("Device 1 config: host=\(config.device1Host), label=\(config.device1Label)")
            DebugLogger.logConfig("Device 2 config: host=\(config.device2Host), label=\(config.device2Label)")
            
            if config.autoStartMonitoring {
                DebugLogger.logUI("Auto-starting monitoring based on user preference")
                Task { @MainActor in
                    self.monitor.startMonitoring()
                }
            } else {
                DebugLogger.logUI("Auto-start disabled - monitoring will not start automatically")
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let statusItem = statusItem else { return }
        guard let button = statusItem.button else { return }
        
        button.target = self
        button.action = #selector(statusItemClicked)
        
        // Don't set a persistent menu - let the action handle it
        statusItem.menu = nil
        
        // Create the initial hosted SwiftUI view
        setupHostedView()
    }
    
    private func setupHostedView() {
        guard let button = statusItem?.button else { return }
        
        let config = NetworkConfiguration.shared
        let statusBarView = StatusBarView(
            device1Label: config.device1Label,
            device1Up: monitor.device1UploadSpeed,
            device1Down: monitor.device1DownloadSpeed,
            device1Latency: monitor.device1Latency ?? 0,
            device1UpFormatted: monitor.device1FormattedUploadSpeed,
            device1DownFormatted: monitor.device1FormattedDownloadSpeed,
            device1LatencyFormatted: monitor.device1FormattedLatency,
            device1PacketLoss: monitor.device1FormattedPacketLoss,
            device2Label: config.device2Label,
            device2Up: monitor.device2UploadSpeed,
            device2Down: monitor.device2DownloadSpeed,
            device2Latency: monitor.device2Latency ?? 0,
            device2UpFormatted: monitor.device2FormattedUploadSpeed,
            device2DownFormatted: monitor.device2FormattedDownloadSpeed,
            device2LatencyFormatted: monitor.device2FormattedLatency,
            device2PacketLoss: monitor.device2FormattedPacketLoss,
            device2Enabled: config.device2Enabled
        )
        
        // Create hosting view if needed
        if hostingView == nil {
            hostingView = NSHostingView(rootView: statusBarView)
            hostingView?.frame = CGRect(x: 0, y: 0, width: config.device2Enabled ? 300 : 150, height: 22)
            button.addSubview(hostingView!)
            
            // Clear button's image and title since we're using a custom view
            button.image = nil
            button.title = ""
        } else {
            // Just update the root view - SwiftUI will handle efficient diffing
            hostingView?.rootView = statusBarView
            hostingView?.frame = CGRect(x: 0, y: 0, width: config.device2Enabled ? 300 : 150, height: 22)
        }
        
        // Update button length to match content
        statusItem?.length = config.device2Enabled ? 300 : 150
    }
    
    private func setupMonitorObservers() {
        // Observe monitor changes and update display - remove throttling for faster updates
        monitor.objectWillChange
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
        
        // Observe configuration changes and update display
        NetworkConfiguration.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateDisplay() {
        // Remove throttling - update immediately when data changes
        // Just update the hosted view - no image conversion needed!
        setupHostedView()
        
        // Update button appearance for error states
        let config = NetworkConfiguration.shared
        let hasErrors = monitor.device1ErrorMessage != nil || (config.device2Enabled && monitor.device2ErrorMessage != nil)
        statusItem?.button?.appearsDisabled = hasErrors
    }

    @objc private func statusItemClicked() {
        guard let statusItem = statusItem else { return }
        
        let config = NetworkConfiguration.shared
        let menu = NSMenu()
        
        // Show real data in menu for enabled devices
        if monitor.isMonitoring {
            // Add history menu items
            let device1HistoryItem = NSMenuItem(title: "View \(config.device1Label) History...", action: #selector(showDevice1History), keyEquivalent: "1")
            device1HistoryItem.target = self
            menu.addItem(device1HistoryItem)
            
            if config.device2Enabled {
                let device2HistoryItem = NSMenuItem(title: "View \(config.device2Label) History...", action: #selector(showDevice2History), keyEquivalent: "2")
                device2HistoryItem.target = self
                menu.addItem(device2HistoryItem)
            }
            
            // Add troubleshooting options if there are errors
            if monitor.device1ErrorMessage != nil || (config.device2Enabled && monitor.device2ErrorMessage != nil) {
                menu.addItem(NSMenuItem.separator())
                let troubleshootItem = NSMenuItem(title: "Troubleshoot Connection Issues...", action: #selector(showTroubleshooting), keyEquivalent: "")
                troubleshootItem.target = self
                menu.addItem(troubleshootItem)
            }
            
        } else {
            menu.addItem(NSMenuItem(title: "Not monitoring", action: nil, keyEquivalent: ""))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Control menu items - dynamically update based on current state
        let startStopTitle = monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring"
        let startStopItem = NSMenuItem(title: startStopTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
        startStopItem.target = self
        menu.addItem(startStopItem)
        
        // Add refresh interfaces option
        if monitor.isMonitoring {
            let refreshItem = NSMenuItem(title: "Refresh Interfaces", action: #selector(refreshInterfaces), keyEquivalent: "r")
            refreshItem.target = self
            menu.addItem(refreshItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Use the standard approach: temporarily set the menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        
        // Clear the menu after it's shown to prevent automatic display
        DispatchQueue.main.async {
            statusItem.menu = nil
        }
    }
    
    private func getDeviceStatusText(
        label: String,
        uploadSpeed: (value: String, unit: String),
        downloadSpeed: (value: String, unit: String),
        latency: String,
        packetLoss: String,
        error: String?
    ) -> (text: String, color: NSColor?) {
        
        if let error = error {
            if error.contains("backing off") || error.contains("temporarily unreachable") {
                return ("\(label): Temporarily unavailable (auto-retry in progress)", .systemOrange)
            } else if error.contains("Interface") {
                return ("\(label): Interface configuration needed", .systemYellow)
            } else {
                return ("\(label): \(error)", .systemRed)
            }
        }
        
        let statusText = String(format: "%@: ↓%@ %@ ↑%@ %@ | %@ ms | Loss: %@",
                               label,
                               downloadSpeed.value, downloadSpeed.unit,
                               uploadSpeed.value, uploadSpeed.unit,
                               latency == "-" ? "-" : latency,
                               packetLoss == "-" ? "-" : packetLoss)
        
        // Color code based on latency using configuration thresholds
        let config = NetworkConfiguration.shared
        let deviceIndex = label == config.device1Label ? 1 : 2
        
        if latency != "-", let latencyValue = Double(latency) {
            return (statusText, config.getLatencyColor(for: deviceIndex, latency: latencyValue))
        }
        
        return (statusText, nil)
    }
    
    @objc private func showTroubleshooting() {
        let alert = NSAlert()
        alert.messageText = "Connection Troubleshooting"
        alert.informativeText = """
        Common solutions for connection issues:
        
        • Check device IP addresses in Settings
        • Verify SNMP is enabled on network devices
        • Ensure community string is correct (usually "public")
        • Check network connectivity to devices
        • Verify SNMP port (default: 161)
        • Try refreshing interfaces if auto-detection failed
        
        For persistent issues, check Console app for detailed logs.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Refresh Interfaces")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            showSettings()
        case .alertSecondButtonReturn:
            refreshInterfaces()
        default:
            break
        }
    }
    
    @objc private func refreshInterfaces() {
        Task { @MainActor in
            await monitor.discoverInterfaces(for: 1)
            if NetworkConfiguration.shared.device2Enabled {
                await monitor.discoverInterfaces(for: 2)
            }
        }
    }
    
    @objc private func toggleMonitoring() {
        Task { @MainActor in
            if self.monitor.isMonitoring {
                self.monitor.stopMonitoring()
            } else {
                self.monitor.startMonitoring()
            }
        }
    }
    
    @objc private func showSettings() {
        // Close existing window if open
        if let existingWindow = settingsWindow {
            existingWindow.close()
            settingsWindow = nil
            
            // Add a small delay before creating new window to avoid ViewBridge issues
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.createSettingsWindow()
            }
        } else {
            createSettingsWindow()
        }
    }
    
    @objc private func showDevice1History() {
        // Close existing window if open
        if let existingWindow = device1HistoryWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        createHistoryWindow(for: 1)
    }
    
    @objc private func showDevice2History() {
        // Close existing window if open
        if let existingWindow = device2HistoryWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        createHistoryWindow(for: 2)
    }
    
    private func createHistoryWindow(for deviceIndex: Int) {
        let config = NetworkConfiguration.shared
        let deviceLabel = deviceIndex == 1 ? config.device1Label : config.device2Label
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        let historyView = NavigationStack {
            NetworkHistoryView(deviceIndex: deviceIndex)
        }
        let hostingController = NSHostingController(rootView: historyView)
        
        window.title = "\(deviceLabel) History"
        window.contentViewController = hostingController
        
        // Set minimum and maximum window sizes
        window.minSize = NSSize(width: 600, height: 500)
        window.maxSize = NSSize(width: 1200, height: 1000)
        
        // Make the window content size fit properly
        window.contentMinSize = NSSize(width: 600, height: 500)
        window.contentMaxSize = NSSize(width: 1200, height: 1000)
        
        window.center()
        window.setFrameAutosaveName("Device\(deviceIndex)History")
        window.delegate = self
        
        // Set window to not be released when closed
        window.isReleasedWhenClosed = false
        
        if deviceIndex == 1 {
            device1HistoryWindow = window
        } else {
            device2HistoryWindow = window
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let settingsView = SettingsView(monitor: monitor) { [weak self] in
            // Use a delay to avoid ViewBridge issues
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.settingsWindow?.orderOut(nil)
                self?.settingsWindow = nil
            }
        }
        let hostingController = NSHostingController(rootView: settingsView)
        
        window.title = "WAN Monitor Settings"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("Settings")
        window.delegate = self
        
        // Set window to not be released when closed
        window.isReleasedWhenClosed = false
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quit() {
        // Cleanup before quitting
        Task { @MainActor in
            await SNMPManager.shared.cancelAllTasks()
        }
        NSApplication.shared.terminate(nil)
    }
    
    deinit {
        // Cleanup
        hostingView = nil
        cancellables.removeAll()
        statusItem = nil
        settingsWindow?.close()
        settingsWindow = nil
        device1HistoryWindow?.close()
        device1HistoryWindow = nil
        device2HistoryWindow?.close()
        device2HistoryWindow = nil
        
        // Cancel all SNMP operations
        Task {
            await SNMPManager.shared.cancelAllTasks()
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                settingsWindow = nil
            } else if window == device1HistoryWindow {
                device1HistoryWindow = nil
            } else if window == device2HistoryWindow {
                device2HistoryWindow = nil
            }
        }
    }
}

// MARK: - SwiftUI Views

struct StatusBarView: View {
    let device1Label: String
    let device1Up: Double
    let device1Down: Double
    let device1Latency: Double
    let device1UpFormatted: (value: String, unit: String)
    let device1DownFormatted: (value: String, unit: String)
    let device1LatencyFormatted: String
    let device1PacketLoss: String
    
    let device2Label: String
    let device2Up: Double
    let device2Down: Double
    let device2Latency: Double
    let device2UpFormatted: (value: String, unit: String)
    let device2DownFormatted: (value: String, unit: String)
    let device2LatencyFormatted: String
    let device2PacketLoss: String
    
    let device2Enabled: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Device 1
            ConnectionStatusIcon(
                label: device1Label,
                uploadFormatted: device1UpFormatted,
                downloadFormatted: device1DownFormatted,
                latencyFormatted: device1LatencyFormatted,
                latencyValue: device1Latency,
                packetLoss: device1PacketLoss
            )
            
            // Only show device 2 if enabled
            if device2Enabled {
                // Device 2
                ConnectionStatusIcon(
                    label: device2Label,
                    uploadFormatted: device2UpFormatted,
                    downloadFormatted: device2DownFormatted,
                    latencyFormatted: device2LatencyFormatted,
                    latencyValue: device2Latency,
                    packetLoss: device2PacketLoss
                )
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 4)
        .frame(height: 22)
    }
}

struct ConnectionStatusIcon: View {
    let label: String
    let uploadFormatted: (value: String, unit: String)
    let downloadFormatted: (value: String, unit: String)
    let latencyFormatted: String
    let latencyValue: Double
    let packetLoss: String

    // Fixed widths for stable columns
    private let speedWidth: CGFloat = 35
    private let unitAndArrowWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: -6) {
            // MARK: Data & Arrow Column
            VStack(alignment: .leading, spacing: -3) {
                // Upload Row
                HStack(spacing: 4) {
                    Text(uploadFormatted.value)
                        .frame(width: speedWidth, alignment: .trailing)
                        .foregroundColor(.white)
                    HStack(spacing: 1) {
                        Text(uploadFormatted.unit)
                            .foregroundColor(.white)
                        Image(systemName: "arrow.up")
                            .foregroundColor(.red)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
                // Download Row
                HStack(spacing: 4) {
                    Text(downloadFormatted.value)
                        .frame(width: speedWidth, alignment: .trailing)
                        .foregroundColor(.white)
                    HStack(spacing: 1) {
                        Text(downloadFormatted.unit)
                            .foregroundColor(.white)
                        Image(systemName: "arrow.down")
                            .foregroundColor(.blue)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
            }
            .monospacedDigit()
            
            // MARK: Label Column - Vertical device label and horizontal latency/loss display
            HStack(spacing: 4) {
                // Vertical device label text stacked like the original "WAN"
                VStack(alignment: .center, spacing: -5) {
                    ForEach(Array(label.uppercased()), id: \.self) { char in
                        Text(String(char))
                            .foregroundColor(.white)
                    }
                }
                .fixedSize()
                
                Spacer()
                    .frame(width: 6)
                
                // Vertical latency and packet loss display
                VStack(alignment: .leading, spacing: -1) {
                    // Latency display
                    Text("\(latencyFormatted)ms")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(latencyColor(latencyValue, label: label))
                    
                    // Packet loss display
                    Text("L:\(packetLoss)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(packetLossColor(packetLoss))
                }
                .frame(width: 55, alignment: .leading)
                .clipped()
            }
        }
    }
    
    private func latencyColor(_ latency: Double, label: String) -> Color {
        let config = NetworkConfiguration.shared
        let deviceIndex = label.uppercased() == config.device1Label.uppercased() ? 1 : 2
        
        return config.getLatencyColorSwiftUI(for: deviceIndex, latency: latency) ?? .white
    }
    
    private func packetLossColor(_ loss: String) -> Color {
        // Parse the percentage (remove % sign if present)
        guard loss != "-" else { return .gray }
        let cleaned = loss.replacingOccurrences(of: "%", with: "")
        guard let lossValue = Double(cleaned) else { return .gray }
        
        if lossValue == 0 {
            return .green
        } else if lossValue < 5 {
            return .yellow
        } else {
            return .red
        }
    }
}
