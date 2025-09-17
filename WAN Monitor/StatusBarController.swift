import AppKit
import SwiftUI
import Combine

class StatusBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: ConnectionMonitor
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    override init() {
        self.monitor = ConnectionMonitor()
        super.init()
        setupStatusItem()
        setupMonitorObservers()
        
        // Wait longer for configuration to load, then start monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("DEBUG: StatusBarController - Starting monitoring after configuration load delay")
            print("DEBUG: Device 1 config: host=\(NetworkConfiguration.shared.device1Host), label=\(NetworkConfiguration.shared.device1Label)")
            print("DEBUG: Device 2 config: host=\(NetworkConfiguration.shared.device2Host), label=\(NetworkConfiguration.shared.device2Label)")
            Task { @MainActor in
                self.monitor.startMonitoring()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let statusItem = statusItem else { return }
        guard let button = statusItem.button else { return }
        
        button.target = self
        button.action = #selector(statusItemClicked)
        
        updateDisplay()
    }
    
    private func setupMonitorObservers() {
        // Observe monitor changes and update display
        monitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
        
        // Observe configuration changes and update display
        NetworkConfiguration.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateDisplay() {
        guard let statusItem = statusItem else { return }
        guard let button = statusItem.button else { return }
        
        let config = NetworkConfiguration.shared
        
        // Create SwiftUI view using real data from both devices
        let swiftUIView = StatusBarView(
            device1Label: config.device1Label,
            device1Up: monitor.device1UploadSpeed,
            device1Down: monitor.device1DownloadSpeed,
            device1Latency: monitor.device1Latency ?? 0.0,
            device1UpFormatted: monitor.device1FormattedUploadSpeed,
            device1DownFormatted: monitor.device1FormattedDownloadSpeed,
            device1LatencyFormatted: monitor.device1FormattedLatency,
            
            device2Label: config.device2Label,
            device2Up: monitor.device2UploadSpeed,
            device2Down: monitor.device2DownloadSpeed,
            device2Latency: monitor.device2Latency ?? 0.0,
            device2UpFormatted: monitor.device2FormattedUploadSpeed,
            device2DownFormatted: monitor.device2FormattedDownloadSpeed,
            device2LatencyFormatted: monitor.device2FormattedLatency
        )
        
        // Render SwiftUI view to image
        if let image = renderSwiftUIViewToImage(swiftUIView) {
            button.image = image
            button.title = ""
        } else {
            // Fallback to simple text for both devices
            let text = String(format: "%@ %.0f↑%.0f↓ %@ %.0f↑%.0f↓",
                             config.device1Label,
                             monitor.device1UploadSpeed * 8 / 1_000_000, // Convert to Mbps
                             monitor.device1DownloadSpeed * 8 / 1_000_000,
                             config.device2Label,
                             monitor.device2UploadSpeed * 8 / 1_000_000,
                             monitor.device2DownloadSpeed * 8 / 1_000_000)
            button.title = text
            button.image = nil
        }
    }
    
    private func renderSwiftUIViewToImage<V: View>(_ view: V) -> NSImage? {
        let hostingController = NSHostingController(rootView: view)
        let targetSize = CGSize(width: 320, height: 22) // Slightly wider for two devices
        
        hostingController.view.frame = CGRect(origin: .zero, size: targetSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layoutSubtreeIfNeeded()
        
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        let cgContext = context!.cgContext
        cgContext.translateBy(x: 0, y: targetSize.height)
        cgContext.scaleBy(x: 1, y: -1)
        
        hostingController.view.layer?.render(in: cgContext)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: targetSize)
        image.addRepresentation(bitmapRep)
        image.isTemplate = false
        
        return image
    }

    @objc private func statusItemClicked() {
        guard let statusItem = statusItem else { return }
        
        let config = NetworkConfiguration.shared
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "WAN Monitor", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Show real data in menu for both devices
        if monitor.isMonitoring {
            // Device 1 info
            let device1Item = NSMenuItem(title: String(format: "%@: ↓%@%@ ↑%@%@ (%@)", 
                                                config.device1Label,
                                                monitor.device1FormattedDownloadSpeed.value,
                                                monitor.device1FormattedDownloadSpeed.unit,
                                                monitor.device1FormattedUploadSpeed.value,
                                                monitor.device1FormattedUploadSpeed.unit,
                                                monitor.device1FormattedLatency == "-" ? "- ms" : "\(monitor.device1FormattedLatency) ms"), 
                                  action: nil, keyEquivalent: "")
            menu.addItem(device1Item)
            
            // Device 2 info
            let device2Item = NSMenuItem(title: String(format: "%@: ↓%@%@ ↑%@%@ (%@)", 
                                                config.device2Label,
                                                monitor.device2FormattedDownloadSpeed.value,
                                                monitor.device2FormattedDownloadSpeed.unit,
                                                monitor.device2FormattedUploadSpeed.value,
                                                monitor.device2FormattedUploadSpeed.unit,
                                                monitor.device2FormattedLatency == "-" ? "- ms" : "\(monitor.device2FormattedLatency) ms"), 
                                  action: nil, keyEquivalent: "")
            menu.addItem(device2Item)
            
            // Show errors if any
            if let error1 = monitor.device1ErrorMessage {
                let errorItem = NSMenuItem(title: "\(config.device1Label) Error: \(error1)", action: nil, keyEquivalent: "")
                errorItem.attributedTitle = NSAttributedString(string: "\(config.device1Label) Error: \(error1)", attributes: [.foregroundColor: NSColor.red])
                menu.addItem(errorItem)
            }
            
            if let error2 = monitor.device2ErrorMessage {
                let errorItem = NSMenuItem(title: "\(config.device2Label) Error: \(error2)", action: nil, keyEquivalent: "")
                errorItem.attributedTitle = NSAttributedString(string: "\(config.device2Label) Error: \(error2)", attributes: [.foregroundColor: NSColor.red])
                menu.addItem(errorItem)
            }
        } else {
            menu.addItem(NSMenuItem(title: "Not monitoring", action: nil, keyEquivalent: ""))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Control menu items
        let startStopTitle = monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring"
        let startStopItem = NSMenuItem(title: startStopTitle, action: #selector(toggleMonitoring), keyEquivalent: "")
        startStopItem.target = self
        menu.addItem(startStopItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Use the menu property instead of deprecated popUpMenu
        statusItem.menu = menu
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
        NSApplication.shared.terminate(nil)
    }
    
    deinit {
        // We can't use Task in deinit, so we need to call stopMonitoring directly
        // The monitor should handle its own cleanup properly
        cancellables.removeAll()
        statusItem = nil
        settingsWindow?.close()
        settingsWindow = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }
}

// Updated StatusBarView to work with dual device data
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
            
            Rectangle()
                .fill(Color.gray)
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
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .foregroundColor(.primary)
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
                        .foregroundColor(.primary)
                    HStack(spacing: 1) {
                        Text(uploadFormatted.unit)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up")
                            .foregroundColor(.red)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
                // Download Row
                HStack(spacing: 4) {
                    Text(downloadFormatted.value)
                        .frame(width: speedWidth, alignment: .trailing)
                        .foregroundColor(.primary)
                    HStack(spacing: 1) {
                        Text(downloadFormatted.unit)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.down")
                            .foregroundColor(.blue)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
            }
            .monospacedDigit()
            
            // MARK: Label Column - Vertical device label and horizontal latency display
            HStack(spacing: 2) {
                // Vertical device label text stacked like the original "WAN"
                VStack(alignment: .center, spacing: -5) {
                    ForEach(Array(label.uppercased()), id: \.self) { char in
                        Text(String(char))
                            .foregroundColor(.primary)
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
            return .red
        } else if latency >= 50 {
            return .orange
        } else {
            return .green
        }
    }
}