# SNMP Metrics Update - Interface Speed, Utilization, and System Uptime

## Summary

This update adds three new important WAN metrics to your monitoring application:

1. **Interface Speed** - The configured speed of the network interface (e.g., 1 Gbps, 10 Gbps)
2. **Interface Utilization** - Percentage of bandwidth being used for upload and download
3. **System Uptime** - How long the device has been running

## Changes Made

### 1. DeviceMonitor.swift

#### New OIDs Added:
```swift
private let ifHighSpeedOID = "1.3.6.1.2.1.31.1.1.1.15"   // Interface speed in Mbps
private let ifSpeedOID = "1.3.6.1.2.1.2.2.1.5"           // Interface speed in bps
private let sysUptimeOID = "1.3.6.1.2.1.1.3.0"           // System uptime
```

#### New Methods:
- `updateInterfaceSpeedAndUtilization()` - Fetches interface speed and calculates utilization percentages
- `updateSystemUptime()` - Retrieves system uptime from SNMP
- Helper methods for formatting speeds and uptime

#### DeviceData Structure:
Added new fields:
- `interfaceSpeed: UInt64?` - Raw speed in bps
- `formattedInterfaceSpeed: String` - Formatted (e.g., "1.0 Gbps")
- `uploadUtilization: Double?` - Upload bandwidth usage (0-100%)
- `downloadUtilization: Double?` - Download bandwidth usage (0-100%)
- `systemUptime: TimeInterval?` - Uptime in seconds
- `formattedSystemUptime: String` - Formatted (e.g., "5d 3h 45m")

### 2. ConnectionMonitor.swift

#### New Published Properties:
For each device (Device 1 and Device 2):
- `@Published var deviceXInterfaceSpeed: UInt64?`
- `@Published var deviceXFormattedInterfaceSpeed: String`
- `@Published var deviceXUploadUtilization: Double?`
- `@Published var deviceXDownloadUtilization: Double?`
- `@Published var deviceXSystemUptime: TimeInterval?`
- `@Published var deviceXFormattedSystemUptime: String`

#### New Methods:
- `updateAllInterfaceMetrics()` - Updates all interface-related metrics for enabled devices
- `updateInterfaceMetrics(for:taskId:)` - Updates speed and utilization for a specific device
- `updateSystemUptime(for:taskId:)` - Updates uptime for a specific device

#### Integration:
- Metrics are updated every 10 monitoring cycles (less frequently than traffic data)
- Non-critical metrics won't cause error messages if they fail
- State is properly reset when monitoring stops

### 3. SettingsView.swift

#### Enhanced DeviceStatusCard:
Now displays:
- **Interface Speed** with speedometer icon
- **System Uptime** with clock icon
- **Upload/Download Utilization** as color-coded percentages below speed values

#### Enhanced MetricView:
- Added optional `utilization` parameter
- Shows utilization percentage with color coding:
  - Green: < 50%
  - Orange: 50-80%
  - Red: > 80%

## How It Works

### Update Frequency
- **Traffic Data**: Every monitoring cycle (~2 seconds by default)
- **Latency**: Based on user's ping interval setting
- **Interface Metrics**: Every 10 cycles (~20 seconds)
- **System Uptime**: Every 10 cycles (~20 seconds)

### Utilization Calculation
```
Utilization % = (Current Speed in bps / Interface Speed in bps) × 100
```

For example:
- Interface Speed: 1 Gbps (1,000,000,000 bps)
- Current Download: 500 Mbps (500,000,000 bps)
- Utilization: 50%

### Uptime Formatting
- Less than 1 hour: Shows minutes only (e.g., "45m")
- Less than 1 day: Shows hours and minutes (e.g., "3h 45m")
- 1 day or more: Shows days, hours, and minutes (e.g., "5d 3h 45m")

## UI Updates

### Settings Window - Status View
When you open Settings and navigate to the Status tab, you'll now see:

1. **Device cards** with expanded information:
   - Current upload/download speeds with utilization percentages
   - Interface speed (e.g., "1.0 Gbps")
   - System uptime (e.g., "5d 3h 45m")

2. **Color-coded utilization**:
   - Green indicators for low utilization (< 50%)
   - Orange for moderate (50-80%)
   - Red for high (> 80%)

## Error Handling

- If interface speed can't be retrieved, it falls back from `ifHighSpeed` to `ifSpeed` OID
- Failed metric updates don't set error messages (they're non-critical)
- Metrics gracefully show "-" when unavailable
- Utilization is automatically clamped to 0-100% range

## SNMP Compatibility

These metrics use standard MIB-II OIDs that should work with:
- Most enterprise routers (Cisco, Juniper, etc.)
- Managed switches
- Network appliances
- Linux devices with SNMP enabled
- Any device supporting RFC 1213 (MIB-II) and RFC 2863 (IF-MIB)

## Testing

To test the new features:

1. Start monitoring from the menu bar
2. Open Settings window
3. Navigate to "Status" in the sidebar
4. You should see:
   - Interface speed for each device
   - Upload/download utilization percentages
   - System uptime

## Future Enhancements

Consider adding:
- Error counters (ifInErrors, ifOutErrors)
- Discard counters (ifInDiscards, ifOutDiscards)
- Multicast/broadcast packet statistics
- TCP connection tracking
- Historical tracking of utilization in charts
- Alerts when utilization exceeds thresholds
