import AppKit
import SwiftUI
import Combine

class StatusBarController {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    
    private var interface1Down: Double = 50
    private var interface1Up: Double = 42
    private var interface1Latency: Double = 8.1
    private var interface2Down: Double = 105
    private var interface2Up: Double = 52
    private var interface2Latency: Double = 81

    init() {
        setupStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startTimer()
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

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateData()
        }
    }

    private func updateData() {
        interface1Down = max(30, interface1Down + Double.random(in: -5...5))
        interface1Up = max(30, interface1Up + Double.random(in: -5...5))
        interface1Latency = max(1.0, interface1Latency + Double.random(in: -0.5...0.5))
        interface2Down = max(80, interface2Down + Double.random(in: -8...8))
        interface2Up = max(40, interface2Up + Double.random(in: -5...5))
        interface2Latency = max(50, interface2Latency + Double.random(in: -3...3))

        DispatchQueue.main.async { [weak self] in 
            self?.updateDisplay() 
        }
    }

    private func updateDisplay() {
        guard let statusItem = statusItem else { return }
        guard let button = statusItem.button else { return }
        
        // Create SwiftUI view using the exact structure from your file
        let swiftUIView = StatusBarView(
            interface1Up: interface1Up,
            interface1Down: interface1Down,
            interface1Latency: interface1Latency,
            interface2Up: interface2Up,
            interface2Down: interface2Down,
            interface2Latency: interface2Latency
        )
        
        // Render SwiftUI view to image
        if let image = renderSwiftUIViewToImage(swiftUIView) {
            button.image = image
            button.title = ""
        } else {
            // Fallback to simple text if rendering fails
            let text = String(format: "%.0f↑%.0f↓HW %.1fms %.0f↑%.0f↓PW %.0fms",
                             interface1Up, interface1Down, interface1Latency,
                             interface2Up, interface2Down, interface2Latency)
            button.title = text
            button.image = nil
        }
    }
    
    private func renderSwiftUIViewToImage<V: View>(_ view: V) -> NSImage? {
        let hostingController = NSHostingController(rootView: view)
        let targetSize = CGSize(width: 280, height: 22)
        
        // Set up the hosting controller properly
        hostingController.view.frame = CGRect(origin: .zero, size: targetSize)
        hostingController.view.wantsLayer = true
        
        // Force layout
        hostingController.view.layoutSubtreeIfNeeded()
        
        // Create bitmap representation
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
        
        // Create graphics context
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        // Flip the coordinate system to fix upside-down rendering
        let cgContext = context!.cgContext
        cgContext.translateBy(x: 0, y: targetSize.height)
        cgContext.scaleBy(x: 1, y: -1)
        
        // Render the view
        hostingController.view.layer?.render(in: cgContext)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create final image
        let image = NSImage(size: targetSize)
        image.addRepresentation(bitmapRep)
        image.isTemplate = false  // Changed to false to preserve colors
        
        return image
    }

    @objc private func statusItemClicked() {
        guard let statusItem = statusItem else { return }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "WAN Monitor", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let hwItem = NSMenuItem(title: String(format: "Hardware WAN: ↓%.0f/↑%.0f Kb/s (%.1fms)", interface1Down, interface1Up, interface1Latency), action: nil, keyEquivalent: "")
        menu.addItem(hwItem)
        
        let pwItem = NSMenuItem(title: String(format: "Point-to-Point WAN: ↓%.0f/↑%.0f Kb/s (%.1fms)", interface2Down, interface2Up, interface2Latency), action: nil, keyEquivalent: "")
        menu.addItem(pwItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(format: "8.8.8.8: %.1fms ✅", interface1Latency), action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: String(format: "1.1.1.1: %.1fms ✅", interface2Latency), action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.popUpMenu(menu)
    }
    
    @objc private func showSettings() {
        let alert = NSAlert()
        alert.messageText = "WAN Monitor Settings"
        alert.informativeText = "Settings panel coming soon!\n\nCurrent configuration:\n• HW Interface: Simulated data\n• PW Interface: Simulated data\n• Update interval: 2 seconds"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        statusItem = nil
    }
}

// MARK: - Mock Data Structures (since we don't have the real ConnectionMonitor)

class MockConnectionMonitor: ObservableObject {
    let upSpeed: Double
    let downSpeed: Double
    let latency: Double
    
    init(upSpeed: Double, downSpeed: Double, latency: Double) {
        self.upSpeed = upSpeed
        self.downSpeed = downSpeed
        self.latency = latency
    }
    
    var formattedUploadSpeed: (value: String, unit: String) {
        (String(format: "%.0f", upSpeed), "Kb/s")
    }
    
    var formattedDownloadSpeed: (value: String, unit: String) {
        (String(format: "%.0f", downSpeed), "Kb/s")
    }
    
    var formattedLatency: String {
        String(format: "%.1f", latency)
    }
    
    var isLatencyMonitoringEnabled: Bool { true }
}

// MARK: - SwiftUI View using your exact ConnectionStatusIcon structure

struct StatusBarView: View {
    let interface1Up: Double
    let interface1Down: Double
    let interface1Latency: Double
    let interface2Up: Double
    let interface2Down: Double
    let interface2Latency: Double
    
    var body: some View {
        HStack(spacing: 6) {
            // Primary Connection (H)
            ConnectionStatusIcon(
                label: "H",
                monitor: MockConnectionMonitor(
                    upSpeed: interface1Up,
                    downSpeed: interface1Down,
                    latency: interface1Latency
                )
            )
            
            Rectangle()
                .fill(Color.gray)
                .frame(width: 1, height: 16)
            
            // Secondary Connection (P)
            ConnectionStatusIcon(
                label: "P",
                monitor: MockConnectionMonitor(
                    upSpeed: interface2Up,
                    downSpeed: interface2Down,
                    latency: interface2Latency
                )
            )
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .foregroundColor(.primary)
        .padding(.horizontal, 4)
        .frame(height: 22)
    }
}

// MARK: - Your exact ConnectionStatusIcon from the file

struct ConnectionStatusIcon: View {
    let label: String
    @ObservedObject var monitor: MockConnectionMonitor

    // Fixed widths for stable columns
    private let speedWidth: CGFloat = 25
    private let unitAndArrowWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: -6) {
            // MARK: Data & Arrow Column
            VStack(alignment: .leading, spacing: 0) {
                // Upload Row
                HStack(spacing: 4) {
                    Text(monitor.formattedUploadSpeed.value)
                        .frame(width: speedWidth, alignment: .trailing)
                        .foregroundColor(.primary)
                    HStack(spacing: 1) {
                        Text(monitor.formattedUploadSpeed.unit)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.up")
                            .foregroundColor(.red)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
                // Download Row
                HStack(spacing: 4) {
                    Text(monitor.formattedDownloadSpeed.value)
                        .frame(width: speedWidth, alignment: .trailing)
                        .foregroundColor(.primary)
                    HStack(spacing: 1) {
                        Text(monitor.formattedDownloadSpeed.unit)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.down")
                            .foregroundColor(.blue)
                    }
                    .frame(width: unitAndArrowWidth, alignment: .leading)
                }
            }
            .monospacedDigit()
            
            // MARK: Label Column - Horizontal latency display with increased size
            HStack(spacing: 2) {
                // Vertical label text
                VStack(alignment: .center, spacing: -4) {
                    ForEach(Array(label), id: \.self) { char in
                        Text(String(char))
                            .foregroundColor(.primary)
                    }
                }
                .fixedSize()
                
                // More compact "WAN" text
                VStack(alignment: .center, spacing: -5) {
                    Text("W")
                        .foregroundColor(.primary)
                    Text("A")
                        .foregroundColor(.primary)
                    Text("N")
                        .foregroundColor(.primary)
                }
                .fixedSize()
                
                Spacer()
                    .frame(width: 6)
                
                // Horizontal latency display next to WAN with fixed width and larger font
                if monitor.isLatencyMonitoringEnabled {
                    Text("\(monitor.formattedLatency)ms")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(latencyColor(monitor.latency))
                        .frame(width: 55, alignment: .leading)
                        .clipped()
                }
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