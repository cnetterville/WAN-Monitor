# Quick Start - New Metrics Guide

## What's New? 🎉

Your WAN Monitor now displays three additional metrics for each monitored device:

### 1. Interface Speed 🔵
Shows the configured speed of your network interface
- Example: `1.0 Gbps`, `100 Mbps`, `10 Gbps`

### 2. Bandwidth Utilization 📊
Shows real-time usage as a percentage of available bandwidth
- Example: `15.2% used` (green), `64.5% used` (orange), `87.3% used` (red)
- Color coded: Green (< 50%), Orange (50-80%), Red (> 80%)

### 3. System Uptime ⏰
Shows how long the device has been running
- Example: `5d 3h 45m` (5 days, 3 hours, 45 minutes)

## Where to See Them?

1. **Click** the menu bar WAN Monitor icon
2. **Select** "Settings..."
3. **Navigate** to "Status" in the left sidebar
4. **View** the enhanced device cards with all metrics

## What to Expect

### During Startup (First 10-20 seconds)
- Metrics will show **"-"** while system initializes
- This is normal! Wait for interface discovery to complete

### During Normal Operation
- Metrics update every ~20 seconds
- Colors change based on utilization levels
- If a metric shows "-", the device may not support it

## Troubleshooting

### All Metrics Show "-"
**Wait 20 seconds** - System is still initializing

### Some Metrics Show "-"
**This is normal** - Not all devices support all metrics

### Metrics Disappeared
**Check connectivity** - May be temporary network issue

### Need More Info?
Check these files:
- `SNMP_METRICS_COMPLETE.md` - Full documentation
- `SNMP_METRICS_FIXES.md` - Technical details

## What's NOT Changed

✅ Traffic monitoring works exactly the same  
✅ Latency and packet loss unchanged  
✅ History graphs still work  
✅ Menu bar display identical  
✅ All existing settings preserved  

The new metrics are **additive** - they enhance but don't change existing functionality.

## Quick Examples

### Healthy Network
```
Interface Speed: 1.0 Gbps
Upload: 45.2 Mbps (4.5% used) 🟢
Download: 128.7 Mbps (12.9% used) 🟢
System Uptime: 45d 12h 34m
```

### Moderate Usage
```
Interface Speed: 1.0 Gbps
Upload: 512.3 Mbps (51.2% used) 🟠
Download: 678.9 Mbps (67.9% used) 🟠
System Uptime: 12d 6h 15m
```

### High Utilization
```
Interface Speed: 1.0 Gbps
Upload: 823.4 Mbps (82.3% used) 🔴
Download: 945.6 Mbps (94.6% used) 🔴
System Uptime: 3d 2h 45m
```

## Benefits

### 1. Capacity Planning
- See how much bandwidth is actually being used
- Plan upgrades based on real utilization data

### 2. Performance Troubleshooting  
- High utilization may indicate bottlenecks
- Low utilization with slow speeds indicates other issues

### 3. Network Health
- System uptime helps identify device restarts
- Interface speed confirms proper link negotiation

## That's It!

The new metrics are automatically collected and displayed. No configuration needed - just start monitoring and check the Status view!
