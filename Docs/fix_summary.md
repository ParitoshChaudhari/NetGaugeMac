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

### 4. Apple App Sandbox Compliance
- **Entitlements**: `com.apple.security.app-sandbox`, `com.apple.security.network.client`, `com.apple.security.network.server`, `com.apple.security.personal-information.location`.
- **Container Auto-Migration**: Automatically copies pre-existing unsandboxed SQLite databases into `~/Library/Containers/com.paritoshchaudhari.NetGaugeMac/Data/Library/Application Support/NetGaugeMac/`.

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
