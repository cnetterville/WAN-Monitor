import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

class StatusBarController: NSObject, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: ConnectionMonitor
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var device1HistoryWindow: NSWindow?
    private var device2HistoryWindow: NSWindow?
    private var lanHistoryWindow: NSWindow?
    
    // MARK: - Hosted SwiftUI View
    private var hostingView: NSHostingView<AnyView>?
    private var lastUpdateTime = Date.distantPast
    private let minUpdateInterval: TimeInterval = 0.1
    
    // Track last data update time for display
    private var lastDataUpdateTime: Date = Date()

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
        
        // Check if compact mode is enabled
        if config.compactMode {
            setupCompactView()
            return
        }
        
        // Determine whether to show latency/loss per device:
        // Always show if the toggle is on, or if latency is at or above the warning threshold
        let device1Latency = monitor.device1Latency ?? 0
        let device2Latency = monitor.device2Latency ?? 0
        let device1ShowLatency = config.device1ShowLatencyLoss ||
            device1Latency >= config.device1LatencyWarningThreshold
        let device2ShowLatency = config.device2ShowLatencyLoss ||
            device2Latency >= config.device2LatencyWarningThreshold
        
        let statusBarView = StatusBarView(
            device1Label: config.device1Label,
            device1Up: monitor.device1UploadSpeed,
            device1Down: monitor.device1DownloadSpeed,
            device1Latency: device1Latency,
            device1UpFormatted: monitor.device1FormattedUploadSpeed,
            device1DownFormatted: monitor.device1FormattedDownloadSpeed,
            device1LatencyFormatted: monitor.device1FormattedLatency,
            device1PacketLoss: monitor.device1FormattedPacketLoss,
            device2Label: config.device2Label,
            device2Up: monitor.device2UploadSpeed,
            device2Down: monitor.device2DownloadSpeed,
            device2Latency: device2Latency,
            device2UpFormatted: monitor.device2FormattedUploadSpeed,
            device2DownFormatted: monitor.device2FormattedDownloadSpeed,
            device2LatencyFormatted: monitor.device2FormattedLatency,
            device2PacketLoss: monitor.device2FormattedPacketLoss,
            device2Enabled: config.device2Enabled,
            lanLabel: config.lanLabel,
            lanUp: monitor.lanUploadSpeed,
            lanDown: monitor.lanDownloadSpeed,
            lanUpFormatted: monitor.lanFormattedUploadSpeed,
            lanDownFormatted: monitor.lanFormattedDownloadSpeed,
            lanEnabled: config.lanEnabled,
            device1ShowLatencyLoss: device1ShowLatency,
            device2ShowLatencyLoss: device2ShowLatency
        )
        
        // Create hosting view if needed
        if hostingView == nil {
            hostingView = NSHostingView(rootView: AnyView(statusBarView))
            button.addSubview(hostingView!)
            button.image = nil
            button.title = ""
        } else {
            hostingView?.rootView = AnyView(statusBarView)
        }
        
        // Size to actual SwiftUI content width rather than hardcoded estimates
        let width = hostingView?.fittingSize.width ?? 200
        hostingView?.frame = CGRect(x: 0, y: 0, width: width, height: 22)
        statusItem?.length = width
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
        // Update last data update time
        lastDataUpdateTime = Date()
        
        // Remove throttling - update immediately when data changes
        // Just update the hosted view - no image conversion needed!
        setupHostedView()
        
        // Update button appearance for error states
        let config = NetworkConfiguration.shared
        let hasErrors = monitor.device1ErrorMessage != nil || 
                       (config.device2Enabled && monitor.device2ErrorMessage != nil) ||
                       (config.lanEnabled && monitor.lanErrorMessage != nil)
        statusItem?.button?.appearsDisabled = hasErrors
    }
    
    private func setupCompactView() {
        guard let button = statusItem?.button else { return }
        
        let config = NetworkConfiguration.shared
        
        // Compact view: show only speeds, no latency
        let compactView = CompactStatusBarView(
            device1Label: config.device1Label,
            device1UpFormatted: monitor.device1FormattedUploadSpeed,
            device1DownFormatted: monitor.device1FormattedDownloadSpeed,
            device2Label: config.device2Label,
            device2UpFormatted: monitor.device2FormattedUploadSpeed,
            device2DownFormatted: monitor.device2FormattedDownloadSpeed,
            device2Enabled: config.device2Enabled,
            lanLabel: config.lanLabel,
            lanUpFormatted: monitor.lanFormattedUploadSpeed,
            lanDownFormatted: monitor.lanFormattedDownloadSpeed,
            lanEnabled: config.lanEnabled
        )
        
        if hostingView == nil {
            hostingView = NSHostingView(rootView: AnyView(compactView))
            button.addSubview(hostingView!)
            button.image = nil
            button.title = ""
        } else {
            hostingView?.rootView = AnyView(compactView)
        }
        
        // Size to actual SwiftUI content width
        let width = hostingView?.fittingSize.width ?? 150
        hostingView?.frame = CGRect(x: 0, y: 0, width: width, height: 22)
        statusItem?.length = width
    }

    @objc private func statusItemClicked() {
        guard let statusItem = statusItem else { return }
        
        let config = NetworkConfiguration.shared
        let menu = NSMenu()
        menu.delegate = self
        
        // IMPROVED: Add current status summary at top of menu
        if monitor.isMonitoring {
            let statusItem = NSMenuItem(title: "Network Status", action: nil, keyEquivalent: "")
            statusItem.attributedTitle = NSAttributedString(
                string: "Network Status",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
            )
            menu.addItem(statusItem)
            
            // Add last update time
            let timeAgo = formatTimeAgo(lastDataUpdateTime)
            menu.addItem(infoMenuItem("    Last updated: \(timeAgo)"))
            
            menu.addItem(NSMenuItem.separator())
            
            // Add detailed status for each device
            addDeviceStatusMenuItem(to: menu, label: config.device1Label,
                                   upload: monitor.device1FormattedUploadSpeed,
                                   download: monitor.device1FormattedDownloadSpeed,
                                   latency: monitor.device1FormattedLatency,
                                   jitter: monitor.device1FormattedJitter,
                                   packetLoss: monitor.device1FormattedPacketLoss,
                                   uptime: monitor.device1DeviceUptime,
                                   rebootDetected: monitor.device1RebootDetected,
                                   connectivityStatus: monitor.device1ConnectivityStatus,
                                   error: monitor.device1ErrorMessage)
            
            if config.device2Enabled {
                addDeviceStatusMenuItem(to: menu, label: config.device2Label,
                                       upload: monitor.device2FormattedUploadSpeed,
                                       download: monitor.device2FormattedDownloadSpeed,
                                       latency: monitor.device2FormattedLatency,
                                       jitter: monitor.device2FormattedJitter,
                                       packetLoss: monitor.device2FormattedPacketLoss,
                                       uptime: monitor.device2DeviceUptime,
                                       rebootDetected: monitor.device2RebootDetected,
                                       connectivityStatus: monitor.device2ConnectivityStatus,
                                       error: monitor.device2ErrorMessage)
            }
            
            if config.lanEnabled {
                addLANStatusMenuItem(to: menu, label: config.lanLabel,
                                    upload: monitor.lanFormattedUploadSpeed,
                                    download: monitor.lanFormattedDownloadSpeed,
                                    error: monitor.lanErrorMessage)
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // IMPROVED: Quick Actions submenu
            let quickActionsItem = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
            let quickActionsMenu = NSMenu()
            
            let copyStatsItem = NSMenuItem(title: "Copy Current Stats", action: #selector(copyCurrentStats), keyEquivalent: "c")
            copyStatsItem.target = self
            quickActionsMenu.addItem(copyStatsItem)
            
            let exportHistoryItem = NSMenuItem(title: "Export History...", action: #selector(exportHistory), keyEquivalent: "e")
            exportHistoryItem.target = self
            quickActionsMenu.addItem(exportHistoryItem)
            
            quickActionsItem.submenu = quickActionsMenu
            menu.addItem(quickActionsItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // History menu items with icons
            let device1HistoryItem = NSMenuItem(title: "View \(config.device1Label) History...", action: #selector(showDevice1History), keyEquivalent: "1")
            device1HistoryItem.target = self
            device1HistoryItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil)
            menu.addItem(device1HistoryItem)
            
            if config.device2Enabled {
                let device2HistoryItem = NSMenuItem(title: "View \(config.device2Label) History...", action: #selector(showDevice2History), keyEquivalent: "2")
                device2HistoryItem.target = self
                device2HistoryItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil)
                menu.addItem(device2HistoryItem)
            }
            
            if config.lanEnabled {
                let lanHistoryItem = NSMenuItem(title: "View \(config.lanLabel) History...", action: #selector(showLANHistory), keyEquivalent: "3")
                lanHistoryItem.target = self
                lanHistoryItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil)
                menu.addItem(lanHistoryItem)
            }
            
            // Add troubleshooting options if there are errors
            if monitor.device1ErrorMessage != nil || (config.device2Enabled && monitor.device2ErrorMessage != nil) {
                menu.addItem(NSMenuItem.separator())
                let troubleshootItem = NSMenuItem(title: "Troubleshoot Connection Issues...", action: #selector(showTroubleshooting), keyEquivalent: "")
                troubleshootItem.target = self
                troubleshootItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
                menu.addItem(troubleshootItem)
            }
            
        } else {
            menu.addItem(infoMenuItem("Not monitoring"))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Control menu items - dynamically update based on current state
        let startStopTitle = monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring"
        let startStopItem = NSMenuItem(title: startStopTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
        startStopItem.target = self
        startStopItem.image = NSImage(systemSymbolName: monitor.isMonitoring ? "stop.circle" : "play.circle", accessibilityDescription: nil)
        menu.addItem(startStopItem)
        
        // Add refresh interfaces option
        if monitor.isMonitoring {
            let refreshItem = NSMenuItem(title: "Refresh Interfaces", action: #selector(refreshInterfaces), keyEquivalent: "r")
            refreshItem.target = self
            refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            menu.addItem(refreshItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // IMPROVED: Display preferences submenu
        let displayPrefsItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        
        let compactModeItem = NSMenuItem(title: "Compact Mode", action: #selector(toggleCompactMode), keyEquivalent: "")
        compactModeItem.target = self
        compactModeItem.state = config.compactMode ? .on : .off
        displayMenu.addItem(compactModeItem)
        
        displayPrefsItem.submenu = displayMenu
        menu.addItem(displayPrefsItem)
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // IMPROVED: About item
        let aboutItem = NSMenuItem(title: "About WAN Monitor", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit WAN Monitor", action: #selector(quit), keyEquivalent: "q")
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
    
    // MARK: - Helper Methods for Menu
    
    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 5 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds) seconds ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
    }
    
    /// Creates a non-interactive menu item with full-brightness text (not grayed).
    private func infoMenuItem(_ text: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        let font: NSFont = bold ? .boldSystemFont(ofSize: 0)
                                : .menuFont(ofSize: 0)
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: font
        ])
        item.isEnabled = false
        return item
    }

    private func addDeviceStatusMenuItem(to menu: NSMenu, label: String,
                                        upload: (value: String, unit: String),
                                        download: (value: String, unit: String),
                                        latency: String,
                                        jitter: String,
                                        packetLoss: String,
                                        uptime: String,
                                        rebootDetected: Bool,
                                        connectivityStatus: String,
                                        error: String?) {
        let indent = "    "
        if let error = error {
            menu.addItem(infoMenuItem("\(indent)\(label): \(error)"))
        } else {
            let latencyStr = jitter == "-" ? "\(latency)" : "\(latency) \(jitter)ms"
            let uptimeSuffix = uptime == "-" ? "" : " | Up: \(uptime)\(rebootDetected ? " ⚠" : "")"
            let connectSuffix = connectivityStatus.isEmpty ? "" : " | \(connectivityStatus)"
            let statusText = "\(indent)\(label): ↓\(download.value) \(download.unit) ↑\(upload.value) \(upload.unit) | \(latencyStr) ms | Loss: \(packetLoss)\(uptimeSuffix)\(connectSuffix)"
            menu.addItem(infoMenuItem(statusText))
        }
    }

    private func addLANStatusMenuItem(to menu: NSMenu, label: String,
                                     upload: (value: String, unit: String),
                                     download: (value: String, unit: String),
                                     error: String?) {
        let indent = "    "
        if let error = error {
            menu.addItem(infoMenuItem("\(indent)\(label): \(error)"))
        } else {
            let statusText = "\(indent)\(label): ↓\(download.value) \(download.unit) ↑\(upload.value) \(upload.unit)"
            menu.addItem(infoMenuItem(statusText))
        }
    }
    
    // MARK: - New Action Methods
    
    @objc private func copyCurrentStats() {
        let config = NetworkConfiguration.shared
        var statsText = "WAN Monitor - Current Statistics\n"
        statsText += "Generated: \(Date())\n\n"
        
        statsText += "\(config.device1Label):\n"
        statsText += "  Upload: \(monitor.device1FormattedUploadSpeed.value) \(monitor.device1FormattedUploadSpeed.unit)\n"
        statsText += "  Download: \(monitor.device1FormattedDownloadSpeed.value) \(monitor.device1FormattedDownloadSpeed.unit)\n"
        statsText += "  Latency: \(monitor.device1FormattedLatency) ms\n"
        statsText += "  Packet Loss: \(monitor.device1FormattedPacketLoss)\n\n"
        
        if config.device2Enabled {
            statsText += "\(config.device2Label):\n"
            statsText += "  Upload: \(monitor.device2FormattedUploadSpeed.value) \(monitor.device2FormattedUploadSpeed.unit)\n"
            statsText += "  Download: \(monitor.device2FormattedDownloadSpeed.value) \(monitor.device2FormattedDownloadSpeed.unit)\n"
            statsText += "  Latency: \(monitor.device2FormattedLatency) ms\n"
            statsText += "  Packet Loss: \(monitor.device2FormattedPacketLoss)\n\n"
        }
        
        if config.lanEnabled {
            statsText += "\(config.lanLabel):\n"
            statsText += "  Upload: \(monitor.lanFormattedUploadSpeed.value) \(monitor.lanFormattedUploadSpeed.unit)\n"
            statsText += "  Download: \(monitor.lanFormattedDownloadSpeed.value) \(monitor.lanFormattedDownloadSpeed.unit)\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(statsText, forType: .string)
        
        // Show notification
        NotificationManager.shared.showNotification(
            title: "Stats Copied",
            message: "Current network statistics copied to clipboard"
        )
    }
    
    @objc private func exportHistory() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "wan-monitor-history-\(Date().formatted(date: .numeric, time: .omitted)).csv"
        savePanel.title = "Export Network History"
        savePanel.message = "Choose a location to save the network history data"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            Task {
                await self.performHistoryExport(to: url)
            }
        }
    }
    
    private func performHistoryExport(to url: URL) async {
        let historyManager = HistoryManager.shared
        let config = NetworkConfiguration.shared
        
        var csvContent = "Timestamp,Device,Upload (Mbps),Download (Mbps),Latency (ms),Packet Loss (%)\n"
        
        // Export Device 1
        for point in historyManager.device1History {
            let upload = point.uploadSpeed * 8 / 1_000_000
            let download = point.downloadSpeed * 8 / 1_000_000
            let latency = point.latency ?? 0
            let packetLoss = point.packetLoss ?? 0
            
            csvContent += "\(point.timestamp),\(config.device1Label),\(upload),\(download),\(latency),\(packetLoss)\n"
        }
        
        // Export Device 2 if enabled
        if config.device2Enabled {
            for point in historyManager.device2History {
                let upload = point.uploadSpeed * 8 / 1_000_000
                let download = point.downloadSpeed * 8 / 1_000_000
                let latency = point.latency ?? 0
                let packetLoss = point.packetLoss ?? 0
                
                csvContent += "\(point.timestamp),\(config.device2Label),\(upload),\(download),\(latency),\(packetLoss)\n"
            }
        }
        
        // Export LAN if enabled
        if config.lanEnabled {
            for point in historyManager.lanHistory {
                let upload = point.uploadSpeed * 8 / 1_000_000
                let download = point.downloadSpeed * 8 / 1_000_000
                
                csvContent += "\(point.timestamp),\(config.lanLabel),\(upload),\(download),N/A,N/A\n"
            }
        }
        
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: "Export Complete",
                    message: "Network history exported successfully"
                )
            }
        } catch {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Could not export history: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    
    @objc private func toggleCompactMode() {
        let config = NetworkConfiguration.shared
        config.compactMode.toggle()
        config.saveConfiguration()
        updateDisplay()
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "WAN Monitor"
        alert.informativeText = """
        Version 1.0
        
        A network monitoring utility for macOS that tracks bandwidth usage and connection quality via SNMP.
        
        Features:
        • Real-time bandwidth monitoring
        • Latency and packet loss tracking
        • Historical data visualization
        • Multi-device support
        
        © 2025 Curtis Netterville
        """
        alert.icon = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        // If window already exists and is visible, just bring it to front
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Close existing window if it exists but isn't visible
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
    
    @objc private func showLANHistory() {
        // Close existing window if open
        if let existingWindow = lanHistoryWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        createHistoryWindow(for: 3)
    }
    
    private func createHistoryWindow(for deviceIndex: Int) {
        let config = NetworkConfiguration.shared
        let deviceLabel: String
        
        if deviceIndex == 1 {
            deviceLabel = config.device1Label
        } else if deviceIndex == 2 {
            deviceLabel = config.device2Label
        } else {
            deviceLabel = config.lanLabel
        }
        
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
        } else if deviceIndex == 2 {
            device2HistoryWindow = window
        } else {
            lanHistoryWindow = window
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
        lanHistoryWindow?.close()
        lanHistoryWindow = nil
        
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
            } else if window == lanHistoryWindow {
                lanHistoryWindow = nil
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
    
    let lanLabel: String
    let lanUp: Double
    let lanDown: Double
    let lanUpFormatted: (value: String, unit: String)
    let lanDownFormatted: (value: String, unit: String)
    
    let lanEnabled: Bool
    let device1ShowLatencyLoss: Bool
    let device2ShowLatencyLoss: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Device 1
            ConnectionStatusIcon(
                label: device1Label,
                uploadFormatted: device1UpFormatted,
                downloadFormatted: device1DownFormatted,
                latencyFormatted: device1LatencyFormatted,
                latencyValue: device1Latency,
                packetLoss: device1PacketLoss,
                showLatency: device1ShowLatencyLoss
            )
            
            // Only show device 2 if enabled
            if device2Enabled {
                // Add spacing between interfaces
                Spacer()
                    .frame(width: 8)
                
                ConnectionStatusIcon(
                    label: device2Label,
                    uploadFormatted: device2UpFormatted,
                    downloadFormatted: device2DownFormatted,
                    latencyFormatted: device2LatencyFormatted,
                    latencyValue: device2Latency,
                    packetLoss: device2PacketLoss,
                    showLatency: device2ShowLatencyLoss
                )
            }
            
            // Only show LAN if enabled
            if lanEnabled {
                // Add spacing between interfaces
                Spacer()
                    .frame(width: 8)
                
                ConnectionStatusIcon(
                    label: lanLabel,
                    uploadFormatted: lanUpFormatted,
                    downloadFormatted: lanDownFormatted,
                    latencyFormatted: "-",
                    latencyValue: 0,
                    packetLoss: "-",
                    showLatency: false // LAN doesn't have latency/packet loss
                )
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 2)  // Reduced from 4 to 2
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
    let showLatency: Bool // Controls whether to show latency/packet loss

    // Fixed widths for stable columns - reduced for tighter layout
    private let speedWidth: CGFloat = 32  // Reduced from 35
    private let unitWidth: CGFloat = 28  // Reduced from 45
    private let arrowWidth: CGFloat = 10  // Reduced from 12

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Data Column - Values aligned right
            VStack(alignment: .trailing, spacing: -3) {
                // Upload value
                Text(uploadFormatted.value)
                    .frame(width: speedWidth, alignment: .trailing)
                    .foregroundColor(.white)
                
                // Download value
                Text(downloadFormatted.value)
                    .frame(width: speedWidth, alignment: .trailing)
                    .foregroundColor(.white)
            }
            .monospacedDigit()
            
            // MARK: Unit & Arrow Column - Units and arrows aligned left
            VStack(alignment: .leading, spacing: -3) {
                // Upload unit and arrow
                HStack(spacing: 0) {  // Reduced from 1 to 0
                    Text(uploadFormatted.unit)
                        .foregroundColor(.white)
                        .frame(minWidth: unitWidth, alignment: .leading)
                    Image(systemName: "arrow.up")
                        .foregroundColor(.red)
                        .frame(width: arrowWidth, alignment: .leading)
                }
                
                // Download unit and arrow
                HStack(spacing: 0) {  // Reduced from 1 to 0
                    Text(downloadFormatted.unit)
                        .foregroundColor(.white)
                        .frame(minWidth: unitWidth, alignment: .leading)
                    Image(systemName: "arrow.down")
                        .foregroundColor(.blue)
                        .frame(width: arrowWidth, alignment: .leading)
                }
            }
            
            // MARK: Label Column - Vertical device label (close to arrows)
            VStack(alignment: .center, spacing: -5) {
                ForEach(Array(label.uppercased()), id: \.self) { char in
                    Text(String(char))
                        .foregroundColor(.white)
                }
            }
            .fixedSize()
            
            // MARK: Latency Column (optional) - Only shown for WAN devices
            if showLatency {
                Spacer()
                    .frame(width: 4)  // Reduced from 6
                
                VStack(alignment: .leading, spacing: -3) {
                    // Latency display
                    Text("\(latencyFormatted)ms")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(latencyColor(latencyValue, label: label))
                    
                    // Packet loss display
                    Text("L:\(packetLoss)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(packetLossColor(packetLoss))
                }
                .frame(width: 48, alignment: .leading)  // Reduced from 55
            }
        }
        .frame(height: 22) // Fixed height to match status bar
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
// MARK: - Compact Status Bar View

struct CompactStatusBarView: View {
    let device1Label: String
    let device1UpFormatted: (value: String, unit: String)
    let device1DownFormatted: (value: String, unit: String)
    
    let device2Label: String
    let device2UpFormatted: (value: String, unit: String)
    let device2DownFormatted: (value: String, unit: String)
    let device2Enabled: Bool
    
    let lanLabel: String
    let lanUpFormatted: (value: String, unit: String)
    let lanDownFormatted: (value: String, unit: String)
    let lanEnabled: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Device 1
            CompactConnectionIcon(
                label: device1Label,
                uploadFormatted: device1UpFormatted,
                downloadFormatted: device1DownFormatted
            )
            
            if device2Enabled {
                Spacer().frame(width: 4)  // Reduced from 6
                
                CompactConnectionIcon(
                    label: device2Label,
                    uploadFormatted: device2UpFormatted,
                    downloadFormatted: device2DownFormatted
                )
            }
            
            if lanEnabled {
                Spacer().frame(width: 4)  // Reduced from 6
                
                CompactConnectionIcon(
                    label: lanLabel,
                    uploadFormatted: lanUpFormatted,
                    downloadFormatted: lanDownFormatted
                )
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 0)  // Removed padding for tighter compact mode
        .frame(height: 22)
    }
}

struct CompactConnectionIcon: View {
    let label: String
    let uploadFormatted: (value: String, unit: String)
    let downloadFormatted: (value: String, unit: String)
    
    // Fixed widths for stable layout
    private let valueWidth: CGFloat = 42  // Increased width for speed value + unit to prevent wrapping
    private let labelWidth: CGFloat = 10  // Width for single letter
    
    var body: some View {
        HStack(spacing: 2) {
            // Label (first letter only) - fixed width
            Text(String(label.prefix(1)).uppercased())
                .foregroundColor(.white)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: labelWidth)
            
            VStack(alignment: .trailing, spacing: -2) {  // Changed to trailing alignment
                // Upload with arrow
                HStack(spacing: 1) {
                    Text(formatCompact(uploadFormatted))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(width: valueWidth, alignment: .trailing)  // Fixed width, right aligned
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7))
                        .foregroundColor(.red)
                }
                
                // Download with arrow
                HStack(spacing: 1) {
                    Text(formatCompact(downloadFormatted))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(width: valueWidth, alignment: .trailing)  // Fixed width, right aligned
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7))
                        .foregroundColor(.blue)
                }
            }
        }
        .fixedSize()  // Prevent the view from expanding
    }
    
    private func formatCompact(_ formatted: (value: String, unit: String)) -> String {
        // Abbreviate units for compact mode
        let unit = formatted.unit
            .replacingOccurrences(of: "bps", with: "")
            .replacingOccurrences(of: "B/s", with: "")
            .replacingOccurrences(of: "ps", with: "")
        
        return "\(formatted.value)\(unit)"
    }
}

