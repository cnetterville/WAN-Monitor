# Cancellation and Uptime Issues - Fixed

## Issues Addressed

### 1. CancellationError Spam
**Problem:**
```
[ERROR] HOU - Traffic update error, circuit breaker failures: 1: CancellationError()
[ERROR] Device 1 traffic update failed: CancellationError()
```

**Root Cause:**
- Tasks were being cancelled when monitoring stopped or restarted
- CancellationError was being treated as a real failure
- Circuit breaker was counting cancellations as failures

**Solution:**
✅ Added explicit `CancellationError` handling in all async methods
✅ Don't record cancellations as circuit breaker failures
✅ Log cancellations as informational, not errors
✅ Check `isMonitoring` flag before starting tasks

### 2. System Uptime Not Showing
**Problem:**
```
[ERROR] snmpwalk failed with status 15
[ERROR] PVR - Failed to get system uptime: connectionTimeout
```

**Root Cause:**
- Status 15 = "No Response" - device doesn't support sysUpTime OID
- System kept retrying even after determining device doesn't support it
- Some devices don't implement MIB-II sysUpTime

**Solution:**
✅ Added `uptimeSupported` flag to DeviceMonitorState
✅ Skip uptime queries if previously determined unsupported
✅ Mark as unsupported on: timeout, invalid response, parse failure
✅ Don't mark as unsupported for temporary errors (network issues)
✅ Enhanced error handling with specific catch blocks

## Changes Made

### ConnectionMonitor.swift

**1. Added monitoring checks:**
```swift
private func updateTrafficDataWithRetry(for deviceIndex: Int, taskId: UUID) async {
    // Check if monitoring is still active before starting
    guard isMonitoring else {
        DebugLogger.logNetwork("Device \(deviceIndex) - Monitoring stopped, skipping")
        return
    }
    // ...
}
```

**2. Added CancellationError handling:**
```swift
} catch is CancellationError {
    // Task was cancelled - this is normal when stopping monitoring
    DebugLogger.logNetwork("Device \(deviceIndex) - Traffic update cancelled")
}
```

**3. Enhanced system uptime error handling:**
```swift
} catch is CancellationError {
    DebugLogger.logSNMP("Device \(deviceIndex) - System uptime query cancelled")
} catch NetworkDiscoveryError.invalidResponse {
    DebugLogger.logSNMP("Device \(deviceIndex) - System uptime not supported by this device")
} catch NetworkDiscoveryError.connectionTimeout {
    DebugLogger.logSNMP("Device \(deviceIndex) - System uptime query timeout (OID may not be supported)")
}
```

### DeviceMonitor.swift

**1. Added uptime support tracking:**
```swift
private actor DeviceMonitorState {
    // ...
    var uptimeSupported: Bool? = nil // nil = unknown, true = supported, false = not supported
    
    func isUptimeSupported() -> Bool? {
        return uptimeSupported
    }
    
    func setUptimeSupported(_ supported: Bool) {
        uptimeSupported = supported
    }
}
```

**2. Enhanced updateSystemUptime:**
```swift
func updateSystemUptime(...) async throws -> (uptime: TimeInterval, formatted: String) {
    // Check if we've already determined uptime is not supported
    if let uptimeSupported = await state.isUptimeSupported(), !uptimeSupported {
        DebugLogger.logSNMP("\(label) - Skipping system uptime (previously determined unsupported)")
        throw NetworkDiscoveryError.invalidResponse
    }
    
    // ... query logic ...
    
    // Mark as supported since we successfully retrieved it
    await state.setUptimeSupported(true)
    
    // ... or mark as unsupported on specific errors ...
    await state.setUptimeSupported(false)
}
```

**3. Added CancellationError handling in traffic updates:**
```swift
} catch {
    // Record failure in circuit breaker only if not a cancellation
    if !(error is CancellationError) {
        currentCircuitBreaker.recordFailure()
        await state.updateCircuitBreaker(currentCircuitBreaker)
        DebugLogger.logError("\(label) - Traffic update error...", error: error)
    } else {
        DebugLogger.logNetwork("\(label) - Traffic update cancelled")
    }
    throw error
}
```

## Error Types and Handling

### CancellationError
- **Cause**: Task cancelled (normal during stop/restart)
- **Handling**: Log as info, don't record as failure
- **Action**: None needed

### NetworkDiscoveryError.connectionTimeout
- **Cause**: Device not responding (SNMP status 15)
- **Handling**: Mark uptime as unsupported for this device
- **Action**: Skip future uptime queries

### NetworkDiscoveryError.invalidResponse
- **Cause**: Unparseable response or unsupported format
- **Handling**: Mark uptime as unsupported
- **Action**: Skip future uptime queries

### Other Errors
- **Cause**: Network issues, temporary problems
- **Handling**: Log but don't mark as permanently unsupported
- **Action**: Retry on next cycle

## Behavior Changes

### Before
```
Every 20 seconds:
- Try to query system uptime
- Get timeout/error
- Log ERROR message
- Increment circuit breaker failures
- Repeat forever...
```

### After
```
First attempt:
- Try to query system uptime
- Get timeout/error
- Mark as unsupported
- Log SNMP debug message (not error)

Future attempts:
- Check if supported
- Skip if not supported
- No error messages
```

## Logging Changes

### Traffic Cancellations
**Before:** `[ERROR] Device 1 traffic update failed: CancellationError()`  
**After:** `[NETWORK] Device 1 - Traffic update cancelled`

### System Uptime Not Supported
**Before:** `[ERROR] Device 1 system uptime update failed: connectionTimeout`  
**After:** `[SNMP] Device 1 - System uptime not supported (timeout)`

### Interface Metrics Cancelled
**Before:** `[ERROR] Device 1 interface metrics update failed: CancellationError()`  
**After:** `[SNMP] Device 1 - Interface metrics cancelled`

## Testing

To verify fixes:

1. **Start Monitoring** - Should see normal startup
2. **Wait 20 seconds** - Interface metrics should load (or show "-" if unsupported)
3. **Check logs** - Should NOT see ERROR for cancellations or unsupported features
4. **Stop/Restart Monitoring** - Should NOT see CancellationError spam
5. **Check Status View** - Uptime shows if supported, "-" if not (no errors)

## Device Compatibility

### Devices That Support sysUpTime
- ✅ Cisco routers and switches
- ✅ Juniper devices
- ✅ Linux with net-snmp (most distributions)
- ✅ Windows Server with SNMP enabled
- ✅ Most managed network equipment

### Devices That May NOT Support sysUpTime
- ⚠️ Consumer routers (limited SNMP)
- ⚠️ Embedded devices
- ⚠️ Older equipment
- ⚠️ Devices with custom SNMP implementations

**For these devices:**
- System uptime will show "-"
- No error messages
- No performance impact
- All other monitoring works normally

## Performance Impact

### Before Fixes
- Uptime query every 20 seconds (even when failing)
- Error logging overhead
- Circuit breaker pollution
- User confusion from error messages

### After Fixes
- First uptime query attempt
- If unsupported: marked and skipped forever
- No repeated failed queries
- No error log spam
- Circuit breaker only tracks real failures

## Summary

✅ **CancellationError handled gracefully**
- Not logged as errors
- Don't trigger circuit breaker
- Normal part of stop/restart cycle

✅ **System uptime truly optional**
- Automatically detected if unsupported
- No repeated failed queries
- No error messages for unsupported devices
- UI shows "-" cleanly

✅ **Cleaner logs**
- Errors only for real problems
- Debug info for expected conditions
- No spam during normal operation

✅ **Better user experience**
- No confusing error messages
- Metrics work on compatible devices
- Graceful degradation on others
- No impact on core monitoring
