import AppKit
import SwiftUI
import Combine

class StatusBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: ConnectionMonitor
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    
    // MARK: - Cached Rendering Components
    private var cachedHostingController: NSHostingController<StatusBarView>?
    private var cachedTargetSize = CGSize(width: 320, height: 22)
    private var lastRenderTime = Date.distantPast
    private let minRenderInterval: TimeInterval = 0.1 // Reduced from 0.5 to allow faster updates

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
        
        updateDisplay()
    }
    
    private func setupMonitorObservers() {
        // Observe monitor changes and update display with less aggressive throttling
        monitor.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main) // Reduced from 500ms to 100ms
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
        
        // Observe configuration changes and update display
        NetworkConfiguration.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main) // Reduced from 200ms to 100ms
            .sink { [weak self] _ in
                // Clear cached controller when config changes
                self?.cachedHostingController = nil
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateDisplay() {
        guard let statusItem = statusItem else { return }
        guard let button = statusItem.button else { return }
        
        // More responsive throttling based on update interval
        let now = Date()
        let config = NetworkConfiguration.shared
        let dynamicRenderInterval = max(0.1, min(config.updateInterval * 0.2, 0.5)) // Scale with user's interval
        guard now.timeIntervalSince(lastRenderTime) >= dynamicRenderInterval else {
            return
        }
        lastRenderTime = now
        
        // Create SwiftUI view
        let statusBarView = StatusBarView(
            device1Label: config.device1Label,
            device1Up: monitor.device1UploadSpeed,
            device1Down: monitor.device1DownloadSpeed,
            device1Latency: monitor.device1Latency ?? 0,
            device1UpFormatted: monitor.device1FormattedUploadSpeed,
            device1DownFormatted: monitor.device1FormattedDownloadSpeed,
            device1LatencyFormatted: monitor.device1FormattedLatency,
            device2Label: config.device2Label,
            device2Up: monitor.device2UploadSpeed,
            device2Down: monitor.device2DownloadSpeed,
            device2Latency: monitor.device2Latency ?? 0,
            device2UpFormatted: monitor.device2FormattedUploadSpeed,
            device2DownFormatted: monitor.device2FormattedDownloadSpeed,
            device2LatencyFormatted: monitor.device2FormattedLatency,
            device2Enabled: config.device2Enabled
        )
        
        // Render SwiftUI view to image for the button
        let image = renderSwiftUIToImage(statusBarView)
        
        // Set the image on the button
        button.image = image
        button.title = ""
        button.imagePosition = .imageOnly
        
        // Add error state coloring if needed
        let hasErrors = monitor.device1ErrorMessage != nil || (config.device2Enabled && monitor.device2ErrorMessage != nil)
        button.appearsDisabled = hasErrors
    }

    // MARK: - SwiftUI to Image Rendering
    
    private func renderSwiftUIToImage<Content: View>(_ content: Content) -> NSImage {
        let targetSize = CGSize(
            width: NetworkConfiguration.shared.device2Enabled ? 300 : 150, 
            height: 22
        )
        
        // Create hosting view
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: targetSize)
        
        // Force layout
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
        
        // Create image representation
        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return NSImage(size: targetSize)
        }
        
        // Cache the display
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
        
        // Create and return the image
        let image = NSImage(size: targetSize)
        image.addRepresentation(bitmapRep)
        
        return image
    }

    @objc private func statusItemClicked() {
        guard let statusItem = statusItem else { return }
        
        let config = NetworkConfiguration.shared
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "WAN Monitor", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Show real data in menu for enabled devices
        if monitor.isMonitoring {
            // Device 1 info with enhanced status
            let device1Status = getDeviceStatusText(
                label: config.device1Label,
                uploadSpeed: monitor.device1FormattedUploadSpeed,
                downloadSpeed: monitor.device1FormattedDownloadSpeed,
                latency: monitor.device1FormattedLatency,
                error: monitor.device1ErrorMessage
            )
            let device1Item = NSMenuItem(title: device1Status.text, action: nil, keyEquivalent: "")
            if let color = device1Status.color {
                device1Item.attributedTitle = NSAttributedString(string: device1Status.text, attributes: [.foregroundColor: color])
            }
            menu.addItem(device1Item)
            
            // Device 2 info - only if enabled
            if config.device2Enabled {
                let device2Status = getDeviceStatusText(
                    label: config.device2Label,
                    uploadSpeed: monitor.device2FormattedUploadSpeed,
                    downloadSpeed: monitor.device2FormattedDownloadSpeed,
                    latency: monitor.device2FormattedLatency,
                    error: monitor.device2ErrorMessage
                )
                let device2Item = NSMenuItem(title: device2Status.text, action: nil, keyEquivalent: "")
                if let color = device2Status.color {
                    device2Item.attributedTitle = NSAttributedString(string: device2Status.text, attributes: [.foregroundColor: color])
                }
                menu.addItem(device2Item)
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
        
        // Show the menu at the status item location
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
    
    private func getDeviceStatusText(
        label: String,
        uploadSpeed: (value: String, unit: String),
        downloadSpeed: (value: String, unit: String),
        latency: String,
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
        
        let statusText = String(format: "%@: ↓%@ %@ ↑%@ %@ (%@ ms)",
                               label,
                               downloadSpeed.value, downloadSpeed.unit,
                               uploadSpeed.value, uploadSpeed.unit,
                               latency == "-" ? "-" : latency)
        
        // Color code based on latency
        if latency != "-", let latencyValue = Double(latency) {
            if latencyValue > 100 {
                return (statusText, .systemRed)
            } else if latencyValue > 50 {
                return (statusText, .systemOrange)
            } else {
                return (statusText, .systemGreen)
            }
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
        // Cleanup cached components
        cachedHostingController = nil
        cancellables.removeAll()
        statusItem = nil
        settingsWindow?.close()
        settingsWindow = nil
        
        // Cancel all SNMP operations
        Task {
            await SNMPManager.shared.cancelAllTasks()
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }
}

// Updated StatusBarView to work with dual device data and support disabling device 2
struct StatusBarView: View {
    let device1Label: String
    let device1Up: Double
    let device1Down: Double
    let device1Latency: Double
    let device1UpFormatted: (value: String, unit: String)
    let device1DownFormatted: (value: String, unit: String)
    let device1LatencyFormatted: String
    
    let device2Label: String
    let device2Up: Double
    let device2Down: Double
    let device2Latency: Double
    let device2UpFormatted: (value: String, unit: String)
    let device2DownFormatted: (value: String, unit: String)
    let device2LatencyFormatted: String
    
    let device2Enabled: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            // Device 1
            ConnectionStatusIcon(
                label: device1Label,
                uploadFormatted: device1UpFormatted,
                downloadFormatted: device1DownFormatted,
                latencyFormatted: device1LatencyFormatted,
                latencyValue: device1Latency
            )
            
            // Only show device 2 if enabled
            if device2Enabled {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1, height: 16)
                
                // Device 2
                ConnectionStatusIcon(
                    label: device2Label,
                    uploadFormatted: device2UpFormatted,
                    downloadFormatted: device2DownFormatted,
                    latencyFormatted: device2LatencyFormatted,
                    latencyValue: device2Latency
                )
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 4)
        .frame(height: 22)
    }
}

// Updated ConnectionStatusIcon to use formatted values
struct ConnectionStatusIcon: View {
    let label: String
    let uploadFormatted: (value: String, unit: String)
    let downloadFormatted: (value: String, unit: String)
    let latencyFormatted: String
    let latencyValue: Double

    // Fixed widths for stable columns
    private let speedWidth: CGFloat = 35  // Increased from 25 to 35
    private let unitAndArrowWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: -6) {
            // MARK: Data & Arrow Column
            VStack(alignment: .leading, spacing: 0) {
                // Upload Row
                HStack(spacing: 4) {
                    Text(uploadFormatted.value)
                        .frame(width: speedWidth, alignment: .trailing)
                        .foregroundColor(.white)
                    HStack(spacing: 1) {
                        Text(uploadFormatted.unit)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
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
                            .fontWeight(.bold)
                        Image(systemName: "arrow.down")
                            .foregroundColor(.blue)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
            }
            .monospacedDigit()
            
            // MARK: Label Column - Vertical device label and horizontal latency display
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
                
                // Horizontal latency display
                Text("\(latencyFormatted)ms")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(latencyColor(latencyValue))
                    .frame(width: 55, alignment: .leading)
                    .clipped()
            }
        }
    }
    
    private func latencyColor(_ latency: Double) -> Color {
        if latency >= 100 {
            return Color(NSColor.systemRed)
        } else if latency >= 50 {
            return Color(NSColor.systemOrange)
        } else {
            return Color(NSColor.systemGreen)
        }
    }
}