# Settings Window - No Unnecessary Restarts

## Problem

Opening the Settings window and clicking "Done" was **always** restarting monitoring, even if no changes were made. This caused:
- ❌ Interruption to active monitoring
- ❌ Loss of connection state
- ❌ Unnecessary reconnection overhead
- ❌ Confusing CancellationError messages
- ❌ Brief data loss during restart

## Solution

Modified SettingsView to **intelligently detect** if changes actually require a restart, and only restart when necessary.

## Changes Made

### SettingsView.swift

**Added State Tracking:**
```swift
// Track if changes require restart
@State private var needsRestart = false

// Store original values to detect changes
@State private var originalDevice1Host = ""
@State private var originalDevice1Community = ""
@State private var originalDevice1Port = 0
@State private var originalDevice1InterfaceName = ""
@State private var originalDevice2Host = ""
@State private var originalDevice2Community = ""
@State private var originalDevice2Port = 0
@State private var originalDevice2InterfaceName = ""
@State private var originalDevice2Enabled = false
@State private var originalLanInterfaceName = ""
@State private var originalLanEnabled = false
```

**Capture Original Values on Open:**
```swift
.onAppear {
    captureOriginalValues()
}

private func captureOriginalValues() {
    originalDevice1Host = configuration.device1Host
    originalDevice1Community = configuration.device1Community
    // ... etc for all critical settings
}
```

**Smart Restart Logic:**
```swift
Button("Done") {
    configuration.saveConfiguration()
    
    // Only restart monitoring if settings changed that require it
    if needsRestartForChanges() {
        Task {
            monitor.stopMonitoring()
            try? await Task.sleep(for: .milliseconds(500))
            monitor.startMonitoring()
        }
    }
    
    onClose()
}
```

**Change Detection:**
```swift
private func needsRestartForChanges() -> Bool {
    // Only restart if monitoring is active and critical settings changed
    guard monitor.isMonitoring else { return false }
    
    // Check if device connection settings changed
    let device1Changed = originalDevice1Host != configuration.device1Host ||
                        originalDevice1Community != configuration.device1Community ||
                        originalDevice1Port != configuration.device1Port ||
                        originalDevice1InterfaceName != configuration.device1InterfaceName
    
    let device2Changed = originalDevice2Host != configuration.device2Host ||
                        originalDevice2Community != configuration.device2Community ||
                        originalDevice2Port != configuration.device2Port ||
                        originalDevice2InterfaceName != configuration.device2InterfaceName ||
                        originalDevice2Enabled != configuration.device2Enabled
    
    let lanChanged = originalLanInterfaceName != configuration.lanInterfaceName ||
                    originalLanEnabled != configuration.lanEnabled
    
    return device1Changed || device2Changed || lanChanged
}
```

## Behavior

### Settings That Require Restart
These changes **will** restart monitoring:
- ✅ Device IP address changed
- ✅ SNMP community string changed
- ✅ SNMP port changed
- ✅ Interface name changed
- ✅ Device 2 enabled/disabled
- ✅ LAN monitoring enabled/disabled
- ✅ LAN interface changed

### Settings That Don't Require Restart
These changes **won't** restart monitoring:
- ✅ Device labels changed (HW, PW, LAN)
- ✅ Ping targets changed
- ✅ Update interval changed
- ✅ Speed display unit changed (bits/bytes)
- ✅ History retention changed
- ✅ Latency color thresholds changed
- ✅ Auto-start preference changed

## User Experience

### Before Fix
```
User: Opens Settings
User: Clicks "Status" to view current data
User: Clicks "Done" (no changes made)
System: Stops monitoring...
System: Starts monitoring...
System: Re-discovers interfaces...
System: Re-establishes connections...
User: Wait... why did it restart? 🤔
```

### After Fix
```
User: Opens Settings
User: Clicks "Status" to view current data
User: Clicks "Done" (no changes made)
System: Saves configuration
System: Continues monitoring seamlessly ✅
User: Perfect! No interruption! 😊
```

## Benefits

✅ **No Unnecessary Interruptions**
- Monitoring continues uninterrupted when just viewing settings
- No data loss during settings window usage

✅ **Faster Settings Access**
- Can quickly check Status view
- Can review history without disrupting monitoring

✅ **Smarter Behavior**
- Only restarts when actually needed
- Detects which specific settings require restart

✅ **Cleaner Logs**
- No spurious "cancelled" messages from unnecessary restarts
- Fewer connection/disconnection log entries

✅ **Better Performance**
- Avoids unnecessary SNMP queries
- Maintains established connections
- Preserves circuit breaker state

## Examples

### Scenario 1: Just Looking Around
```
1. User opens Settings
2. Navigates to "Status" tab
3. Checks current metrics
4. Clicks "Done"
Result: No restart! Monitoring continues seamlessly.
```

### Scenario 2: Changing Display Preferences
```
1. User opens Settings
2. Changes device label from "HW" to "Home"
3. Changes speed display from bits to bytes
4. Clicks "Done"
Result: No restart! UI updates, monitoring continues.
```

### Scenario 3: Changing Connection Settings
```
1. User opens Settings
2. Changes Device 1 IP from 192.168.1.1 to 192.168.1.2
3. Clicks "Done"
Result: Restart! New IP requires reconnection.
```

### Scenario 4: Enabling Device 2
```
1. User opens Settings
2. Enables Device 2 monitoring
3. Configures Device 2 IP and community
4. Clicks "Done"
Result: Restart! New device requires initialization.
```

## Technical Details

### Why 500ms Delay?
```swift
try? await Task.sleep(for: .milliseconds(500))
```

The 500ms delay between stop and start ensures:
- Clean shutdown of existing SNMP connections
- Circuit breakers reset properly
- Active tasks complete or cancel
- State is fully cleared before restart

### Restart Trigger Logic

**Connection Settings** (always require restart):
- Host IP address
- SNMP community string
- SNMP port
- Interface selection

**Enable/Disable** (requires restart):
- Device 2 enable toggle
- LAN monitoring enable toggle

**Display Settings** (no restart needed):
- Device labels (UI only)
- Speed units (formatting only)
- Color thresholds (display only)

**Monitoring Settings** (no restart needed):
- Update interval (applied on next cycle)
- Ping interval (applied on next ping)
- History retention (background cleanup)

## Testing

To verify the fix:

1. **Test No Changes:**
   - Open Settings
   - Click "Done" immediately
   - ✅ Should not see restart messages in logs

2. **Test Label Change:**
   - Open Settings
   - Change device label
   - Click "Done"
   - ✅ Should not restart monitoring

3. **Test IP Change:**
   - Open Settings
   - Change device IP address
   - Click "Done"
   - ✅ Should restart monitoring

4. **Test Enable Device:**
   - Open Settings
   - Enable Device 2
   - Click "Done"
   - ✅ Should restart monitoring

## Future Enhancements

Possible improvements:
- [ ] Show "Restart Required" indicator when changes need restart
- [ ] Add "Apply" button that restarts immediately
- [ ] Add "Revert" button to cancel changes
- [ ] Show which specific settings changed
- [ ] Allow manual restart from settings

## Summary

✅ **Problem:** Settings window always restarted monitoring  
✅ **Solution:** Smart detection of changes that require restart  
✅ **Result:** Monitoring only restarts when necessary  
✅ **Benefit:** Seamless user experience, no unnecessary interruptions  

Users can now open Settings to check Status or History without disrupting active monitoring!
