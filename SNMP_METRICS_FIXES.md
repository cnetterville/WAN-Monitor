# SNMP Metrics Error Fixes

## Issues Fixed

The initial implementation had several errors when trying to fetch interface speed, utilization, and system uptime:

1. **Interface Not Found Errors** - Trying to query interface-specific metrics before interfaces were discovered
2. **Invalid Response Errors** - System uptime returns TimeTicks format which wasn't being parsed correctly
3. **Device Unreachable Errors** - Non-critical metrics were failing when devices had temporary connectivity issues

## Changes Made

### 1. SNMPManager.swift

**Added new method for string responses:**
```swift
func performSnmpGetString(host:community:oid:updateInterval:taskId:) async throws -> String
```

This method retrieves SNMP values as strings, which is necessary for:
- TimeTicks (system uptime)
- String values
- Special formatted responses

The method uses the same process management and error handling as the existing `performSnmpGet` method.

### 2. DeviceMonitor.swift

**Enhanced Interface Speed Query:**
- Added check to ensure interface index exists before querying
- Added detailed logging for debugging
- Better error messages distinguishing between "no interface set" vs "query failed"

**Fixed System Uptime Parsing:**
The uptime method now handles multiple formats:
- **Timeticks format**: `"Timeticks: (12345678) 1 day, 10:17:36.78"`
- **Plain number format**: `"12345678"`

Parsing logic:
```swift
if uptimeString.contains("(") && uptimeString.contains(")") {
    // Extract number between parentheses
    let numberString = String(uptimeString[start..<end])
    uptimeValue = UInt64(numberString)
} else {
    // Plain number
    uptimeValue = UInt64(uptimeString)
}
```

### 3. ConnectionMonitor.swift

**Smarter Error Handling:**

**For Interface Metrics:**
```swift
// Only try to get metrics if we have valid traffic data
guard currentUploadSpeed > 0 || currentDownloadSpeed > 0 else {
    DebugLogger.logSNMP("Skipping interface metrics (no traffic data yet)")
    return
}
```

**For Interface Not Found:**
```swift
catch NetworkDiscoveryError.interfaceNotFound {
    // Expected when interfaces haven't been discovered yet
    DebugLogger.logSNMP("Interface not found, will retry after discovery")
}
```

**For System Uptime Failures:**
```swift
catch NetworkDiscoveryError.invalidResponse {
    // Device might not support sysUpTime OID
    DebugLogger.logSNMP("System uptime not supported or invalid format")
}
```

**Key improvements:**
- Non-critical metrics don't show error messages to users
- Logging uses `logSNMP` instead of `logError` for expected conditions
- Graceful degradation - app continues working even if these metrics fail

## Why These Errors Occurred

### 1. Interface Not Found
The interface metrics query was happening before interface discovery completed. The fix:
- Wait for traffic data before querying interface speed (traffic data requires interfaces)
- Silently skip when interface index isn't set yet
- Retry automatically on next cycle after interfaces are discovered

### 2. Invalid Response for System Uptime
SNMP returns system uptime as a **TimeTicks** type, which has special formatting:
```
Timeticks: (1234567890) 142 days, 21:21:18.90
```

The original code tried to parse this directly as `UInt64`, which failed. The fix:
- Use `performSnmpGetString` to get raw response
- Parse the number from between parentheses
- Convert timeticks (hundredths of seconds) to seconds

### 3. Device Unreachable
When devices temporarily lose connectivity, the circuit breaker kicks in. The fix:
- These are non-critical metrics, so failures don't stop monitoring
- Errors are logged but not shown to users
- Metrics automatically retry on next cycle when connectivity returns

## Testing Results

After fixes:
- ✅ Interface speed queries work once interfaces are discovered
- ✅ System uptime correctly parses TimeTicks format
- ✅ Failures don't spam error logs or show errors to users
- ✅ Metrics gracefully retry when conditions improve
- ✅ App continues monitoring traffic even if these metrics fail

## Expected Behavior Now

### On Startup
1. Monitoring starts
2. Interface discovery runs (5 seconds)
3. Traffic data starts collecting (~2 seconds)
4. After 10 cycles (~20 seconds), interface metrics attempted
   - If interfaces discovered: ✅ Speed and utilization shown
   - If not: Silently skips, retries next cycle
5. System uptime attempted
   - If supported: ✅ Uptime shown
   - If not supported: Silently skips

### During Operation
- Interface metrics update every ~20 seconds
- System uptime updates every ~20 seconds
- Failures are logged but don't affect user experience
- Metrics show "-" when unavailable (not error messages)

## Logging Changes

Before (Error):
```
[ERROR] Device 1 interface metrics update failed: interfaceNotFound
[ERROR] Device 1 system uptime update failed: invalidResponse
```

After (Debug):
```
[SNMP] Device 1 - Skipping interface metrics (no traffic data yet)
[SNMP] Device 1 - System uptime not supported or invalid format
```

These messages only appear in debug logs, not in user-facing error messages.

## Future Improvements

1. **Cache interface speed** - Once obtained, cache for entire monitoring session
2. **Lazy loading** - Only fetch these metrics when Settings > Status view is open
3. **User toggle** - Allow disabling these metrics in preferences if causing issues
4. **Device profiles** - Remember which devices support which metrics
5. **Fallback OIDs** - Try alternate OIDs if standard ones fail

## Compatibility Notes

### System Uptime Support
Most devices support `sysUpTime` (OID 1.3.6.1.2.1.1.3.0):
- ✅ Cisco routers and switches
- ✅ Juniper devices
- ✅ Linux with net-snmp
- ✅ Most SNMP-enabled network equipment
- ⚠️ Some embedded devices may not support it

### Interface Speed Support
Most modern devices support both OIDs:
- `ifHighSpeed` (1.3.6.1.2.1.31.1.1.1.15) - Mbps, for Gigabit+
- `ifSpeed` (1.3.6.1.2.1.2.2.1.5) - bps, older standard

The code tries high-speed first, falls back to regular speed.
