//
//  DataExporter.swift
//  WAN Monitor
//
//  Created by AI Assistant
//

import Foundation
import AppKit

class DataExporter {
    static let shared = DataExporter()
    
    private init() {}
    
    func exportToCSV(data: [(timestamp: Date, device1Upload: Double, device1Download: Double, device1Latency: Double?, device2Upload: Double?, device2Download: Double?, device2Latency: Double?)]) -> URL? {
        guard !data.isEmpty else { return nil }
        
        var csvContent = "Timestamp,Device1_Upload_Mbps,Device1_Download_Mbps,Device1_Latency_ms,Device2_Upload_Mbps,Device2_Download_Mbps,Device2_Latency_ms\n"
        
        for entry in data {
            let device2Upload = entry.device2Upload.map { String(format: "%.2f", $0 * 8 / 1_000_000) } ?? ""
            let device2Download = entry.device2Download.map { String(format: "%.2f", $0 * 8 / 1_000_000) } ?? ""
            let device2Latency = entry.device2Latency.map { String(format: "%.1f", $0) } ?? ""
            
            csvContent += String(format: "%@,%.2f,%.2f,%@,%@,%@,%@\n",
                               ISO8601DateFormatter().string(from: entry.timestamp),
                               entry.device1Upload * 8 / 1_000_000,
                               entry.device1Download * 8 / 1_000_000,
                               entry.device1Latency.map { String(format: "%.1f", $0) } ?? "",
                               device2Upload,
                               device2Download,
                               device2Latency)
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("wan-monitor-export.csv")
        try? csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    func showExportDialog() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Network Data"
        savePanel.nameFieldStringValue = "network-data-\(DateFormatter.filename.string(from: Date())).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        
        if savePanel.runModal() == .OK {
            // Implementation would need data collection system
            // This is a placeholder for the export functionality
        }
    }
}

extension DateFormatter {
    static let filename: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}