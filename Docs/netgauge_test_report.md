# NetGaugeMac — Comprehensive Test & Audit Report

> **Date**: 29 July 2026  
> **App**: NetGaugeMac v1.0.2 (Sandboxed)  
> **Files Analyzed**: `App.swift`, `DashboardModel.swift`, `DashboardView.swift`, `UsageStore.swift`, `NetworkSampler.swift`

---

## Executive Summary

NetGaugeMac is a native macOS menu-bar network monitor with SQLite-based tiered retention. This audit document tracks all real-world test scenarios, identified issues, and verification steps for feature accuracy.

---

## Part 1: Real-World Test Scenarios & Results

### Scenario 1: "Wi-Fi SSID Resolution & Connection Switch"
- **Expected**: Active Wi-Fi SSID displayed as `"Wi-Fi: <SSID>"` in Usage by Network panel.
- **Root Cause of Issue**: `SCNetworkInterfaceGetLocalizedDisplayName` returned `"Wi-Fi / Ethernet (en0)"` which failed strict `displayName == "Wi-Fi"` check, falling through to generic `"Wi-Fi"`.
- **Fix Applied**: Updated `getNetworkName` to check `displayName.localizedCaseInsensitiveContains("Wi-Fi")` and iterate all CoreWLAN `CWInterface`s. Enhanced `LocationHelper` to request location updates for macOS 14+ authorization.
- **Status**: ✅ **RESOLVED**

### Scenario 2: "Heavy Download — 32-Bit Kernel Counter Wrap"
- **Expected**: Continuous download calculation without traffic loss when `getifaddrs` 32-bit counter wraps at ~4.29 GB.
- **Root Cause of Issue**: `safeDelta` returned `0` when `current < previous`, dropping ~1 second of data per wrap.
- **Fix Applied**: Updated `safeDelta` to calculate wrap delta: `(UInt64(UInt32.max) - previous) + current + 1`.
- **Status**: ✅ **RESOLVED**

### Scenario 3: "30-Day & Custom Range Bandwidth Queries"
- **Expected**: Non-overlapping sums across minute, hour, and day tiers.
- **Root Cause of Issue**: `UNION ALL` queries used expanded inclusive bounds (`<=`), double-counting data at tier boundaries.
- **Fix Applied**: Redesigned queries to use exact exclusive upper bounds (`<`) (`ts >= startTs AND ts < endTs`).
- **Status**: ✅ **RESOLVED**

### Scenario 4: "Historical Usage by Network (Month Totals)"
- **Expected**: Monthly usage sums include data rolled up to `network_days` table (>90 days old).
- **Root Cause of Issue**: `sqlMonth` only queried `network_minutes` and `network_hours`.
- **Fix Applied**: Added `UNION ALL SELECT network_name, bytes_rx, bytes_tx FROM network_days WHERE ts >= ?` to `sqlMonth`.
- **Status**: ✅ **RESOLVED**

### Scenario 5: "App Sandbox Execution (`com.apple.security.app-sandbox`)"
- **Expected**: App runs isolated in App Sandbox container with network, location, and file privileges.
- **Fix Applied**: Created `NetGaugeMac.entitlements`, configured `Info.plist`, implemented container database auto-migration in `UsageStore.swift`, and signed with `codesign`.
- **Status**: ✅ **RESOLVED**

---

## Part 2: Automated Accuracy Test Suite

NetGaugeMac includes an automated test runner (`NetGaugeMacTestRunner`) that validates:
1. `32-Bit Counter Wrap Delta Accuracy`
2. `Multi-Address Interface Accumulation`
3. `Usage Bucket ID Uniqueness`
4. `Custom Date Range Ordering`
5. `Non-Overlapping Tier Boundary Query`

To run the automated accuracy test suite:
```bash
swift run NetGaugeMacTestRunner
```
