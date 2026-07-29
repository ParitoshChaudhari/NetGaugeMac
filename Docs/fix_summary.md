# NetGaugeMac — Fix Summary & Troubleshooting Guide

## Applied Fixes Overview

### 1. Wi-Fi Network SSID Resolution
- **Issue**: "Usage by Network" displayed generic `"Wi-Fi"` instead of specific SSID `"Wi-Fi: <SSID>"`.
- **Root Cause**: 
  1. `SCNetworkInterfaceGetLocalizedDisplayName` returned `"Wi-Fi / Ethernet (en0)"` which failed strict equality check `displayName == "Wi-Fi"`.
  2. On macOS Sonoma (14.0+) & Sequoia (15.0+), Apple redacts Wi-Fi SSIDs unless Location Services permission is granted.
- **Solution**:
  - Changed condition to `displayName.localizedCaseInsensitiveContains("Wi-Fi") || isWifi || interfaceName == "en0"`.
  - Added fallback loop over `CWWiFiClient.shared().interfaces()` to find active SSID.
  - Enhanced `LocationHelper` to request location updates so macOS authorizes CoreWLAN SSID access.
- **Wi-Fi SSID Display Rules**:
  - **Connected to Wi-Fi AP + Location Authorized**: Displays `"Wi-Fi: <SSID>"` (e.g., `"Wi-Fi: Home_Network"`).
  - **Wi-Fi Disconnected / Tethered via USB / Hotspot**: Displays `"Wi-Fi"`, `"Ethernet"`, or `"iPhone USB Hotspot"`.

### 2. 32-Bit Kernel Counter Overflow
- **Issue**: Under sustained high-speed downloads, ~3-30% of bandwidth was lost.
- **Solution**:
  - In `DashboardModel.safeDelta`:
    ```swift
    if current >= previous { return current - previous }
    return (UInt64(UInt32.max) - previous) + current + 1
    ```

### 3. Tier Query Double-Counting
- **Issue**: Summing minute, hour, and day tables with overlapping ranges inflated metrics.
- **Solution**:
  - Enforced exclusive upper bounds `ts >= startTs AND ts < endTs` across all queries.
  - Wrapped `UNION ALL` statements in subquery for global `ORDER BY ts ASC`.

### 5. Settings Tab & Data Reset ("Clear All Data")
- **Feature**: Added a dedicated Settings tab with General Preferences, Location Status, Database Path info, and a Danger Zone "Clear All Data" button.
- **Confirmation Warning**: Prompts the user with a native macOS warning alert:
  > *Clear All Network Data? This will permanently delete all recorded network speed and usage history and reset NetGauge to its fresh install state. This action cannot be undone.*
- **Reset Mechanism**:
  - Truncates all SQLite tables (`network_minutes`, `network_hours`, `network_days`, `network_usage`) and runs `VACUUM`.
  - Clears all in-memory buffers (`inMemorySamples`, `networkUsageDeltas`, `ssidCache`, `interfaceRates`).
  - Resets kernel snapshot baselines so new traffic accumulates from zero.

### 6. macOS 26 SwiftUI `LocalizedStringKey` Format String Crash
- **Issue**: App crashed with `__CF_IS_OBJC(0x0)` / `__CFStringAppendFormatCore` null pointer when rendering dynamic strings containing `%`, `/`, or date formats.
- **Solution**: Explicitly initialized all dynamic text views using `Text(verbatim:)` across `HeroMetric`, `RateTile`, `MiniStatCard`, `InterfaceRateRow`, `NetworkUsageRow`, `ChartTooltipCard`, `TooltipRow`, and date footers.

### 7. CoreLocation API & SSID Disambiguation
- **Issue**: macOS Location permission request failed due to using iOS-only `requestAlwaysAuthorization()`.
- **Solution**: Switched to `requestWhenInUseAuthorization()`. Added `"Wi-Fi (interfaceName)"` fallback so unresolvable SSIDs stay separated by physical adapter instead of collapsing into a single `"Wi-Fi"` row. Added a 30-second SSID lookup cache to eliminate main thread IPC latency.

---

## How to Run & Validate Tests

To run the automated accuracy test suite at any time:
```bash
swift run NetGaugeMacTestRunner
```

Expected output:
```text
=========================================
  NetGaugeMac Accuracy & Feature Suite   
=========================================
✅ [PASS] 32-Bit Counter Wrap Delta Accuracy
✅ [PASS] Multi-Address Interface Accumulation
✅ [PASS] Usage Bucket ID Uniqueness
✅ [PASS] Custom Date Range Ordering
✅ [PASS] Non-Overlapping Tier Boundary Query
=========================================
Results: 5 Passed, 0 Failed
=========================================
```
