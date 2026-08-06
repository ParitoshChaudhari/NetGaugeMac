# NetGauge — Native macOS Real-time Traffic & Analytics Monitor

NetGauge is a native macOS utility application that tracks real-time network download and upload speeds directly in your Menu Bar and offers detailed, range-aware bandwidth analytics inside a modern dashboard. 

The application is built on top of Apple's developer guidelines (HIG) using SwiftUI, Swift 6 strict concurrency, and raw `SQLite3` database persistence (zero-dependency).

---

## Key Features

* **Real-time Menu Bar Speedometer**: Displays stacked download (`↓`) and upload (`↑`) speeds dynamically in a monospaced font directly in the system status bar, updating every second.
* **Continuous Background Tracking**: Closing the dashboard window switches the application's activation policy to `.accessory` mode. The app continues network sampling silently in the background, keeping the Dock clean and preserving tracking integrity.
* **Dynamic Range-Aware Dashboard**: All metrics (Hero Cards, Rate Strip, and Network Performance card) dynamically adapt to the selected range (**1D/Today**, **Yday/Yesterday**, **1M/Month**, **30D**, or **Custom**):
  * **Hero Cards**: Displays total, peak, and quietest periods calculated specifically for the selected date range.
  * **Dynamic Comparison Deltas**: Automatically calculates percentage gains/losses against relative prior periods (e.g., Yesterday compares vs the day before yesterday; Last 30 Days compares vs the prior 30-day window).
  * **Rate Strip**: Displays selected range totals alongside appropriate reference totals (e.g., showing Selected Total and Today Total when viewing 30D).
* **Dedicated Settings & Preferences Tab**: Integrated top navigation tab bar (`[ 📊 Dashboard ]  [ ⚙️ Settings ]`) and status menu `Settings...` shortcut (`Cmd+,`) for easy access to configuration.
* **Liquid Glass Theme**: Optional Apple-inspired Liquid Glass material design with backdrop blur, specular edge highlights, dynamic glass depth, and configurable transparency slider.
* **Complete App Reset & "Clear All Data"**: Reset option inside Settings to wipe all SQLite usage history (`network_minutes`, `network_hours`, `network_days`, `network_usage`), clear in-memory buffers, and reset kernel baselines back to fresh install state, guarded by a native macOS warning confirmation dialog.
* **Granular SSID & Connection Tracking**:
  * Resolves physical interface counters (like `en0`) into logical networks (e.g. `"Wi-Fi: MySSID"`, `"iPhone USB Hotspot"`, `"Ethernet"`).
  * Integrates with Location Services (`CLLocationManager`) to securely read Wi-Fi SSIDs on macOS Sonoma and later.
  * Disambiguates unresolvable Wi-Fi interfaces as `"Wi-Fi (en0)"` so separate physical network adapters maintain distinct database history.
  * **"Usage by Network"** list displaying Today usage, Month usage, and Cumulative totals side-by-side.
* **Interactive Network Filtering**: Clicking any network card or choosing a network from the chart dropdown focuses all dashboard charts, totals, peak metrics, and performance grids on that network.
* **Clean Active Interfaces View**: Automatically filters out inactive virtual interfaces (e.g. idle `awdl`, `bridge`, `anpi` showing 0 B/s), keeping the panel focused on active connections and primary adapters.
* **SQLite Tiered Retention Strategy**:
  * **Raw samples (1/sec)**: Kept in memory only — never hits disk.
  * **Minute aggregation**: Every 60s, aggregated rows are written to `network_minutes` grouped by `(ts, network_name)` composite keys.
  * **Hourly rollup (7 days)**: Minute rows older than 7 days are rolled up into `network_hours` (timezone-safe).
  * **Daily rollup (90 days)**: Hourly rows older than 90 days are rolled up into `network_days` and retained indefinitely, keeping database footprint minimal forever.
  * **Self-Healing Migrator**: Automatically upgrades older single-primary-key schemas to composite-key schemas on launch with zero data loss.
* **Auto-Start on Boot**: Login item registration (`SMAppService`) with a smart system uptime heuristic: if launched within 120 seconds of boot, it starts hidden in the Menu Bar automatically.
* **Drag-and-Drop Installation**: Distributed as a native installer disk image (`NetGaugeMac.dmg`).
* **High-Res App Icon & Developer Credits**: Dynamically loaded application icon with developer credits to **Paritosh Chaudhari**.

---

## Technical Details

- **Language**: Swift 5.10 / Swift 6
- **Frameworks**: SwiftUI, AppKit, Charts, CoreWLAN, CoreLocation, SystemConfiguration, ServiceManagement
- **Database**: SQLite3 (native libsqlite3 system library, zero-dependency, `FULLMUTEX` thread-safe)
- **Minimum OS**: macOS 14 Sonoma (uses modern `SMAppService` and Swift Charts APIs)
- **Security**: Apple App Sandbox (`com.apple.security.app-sandbox`) with Network Client, Network Server, Location, and User File privileges

---

## File Structure

* **App.swift**: Main application entry point, status menu item setup, multiline speed renderer, close button event interception, custom About panel, wake-from-sleep status item recovery, and boot startup heuristics.
* **DashboardModel.swift**: `@MainActor` state manager, 1-second capture loop, in-memory buffers with auto-flush at capacity, interface bandwidth rate logic, safe delta overflow handling, and `SMAppService` toggle bindings.
* **DashboardView.swift**: SwiftUI dashboard view, custom design system tokens, 45-degree rotated X-axis labels, dropdown network filter, interactive network cards, and Liquid Glass theme support.
* **UsageStore.swift**: Serial actor-isolated raw `sqlite3` database engine with `FULLMUTEX` thread safety, schema migration scripts, sandboxed container migration, composite-key aggregation, and timezone-aligned rollup jobs.
* **NetworkSampler.swift**: Stateless network byte counters queried from Kernel BSD `getifaddrs` API with safe `UInt32` flag handling and null-pointer guards.
* **VisualEffectView.swift**: SwiftUI wrapper for `NSVisualEffectView` enabling native macOS backdrop blur and vibrancy.
* **NetGaugeMac.entitlements**: Apple App Sandbox entitlements configuration.

---

## Version History

### v1.0.4 — Stability & Crash Fix Release (August 2026)

Comprehensive audit and fix of **22 bugs** across all source files targeting crashes and menu bar indicator reliability.

#### Crash Fixes
| Fix | File | Impact |
|-----|------|--------|
| Changed SQLite from `SQLITE_OPEN_NOMUTEX` to `SQLITE_OPEN_FULLMUTEX` | UsageStore.swift | Prevents database corruption under Swift actor reentrancy |
| All `UInt64 → Int64` casts now use `Int64(clamping:)` | UsageStore.swift, DashboardModel.swift | Prevents integer overflow trap on very large byte totals |
| Fixed `Int32(ifa_flags)` to use `UInt32` comparisons | NetworkSampler.swift | Prevents crash when kernel sets MSB on interface flags |
| Set `window.isReleasedWhenClosed = false` | App.swift | Prevents dangling pointer on system force-close |
| Replaced async `NSAnimationContext.runAnimationGroup` with synchronous grouping | App.swift | Prevents race between animation completion and `orderOut` |
| Wrapped `handlePowerOff` in `Task { @MainActor in }` | App.swift | Prevents data race on shutdown flag from background thread |
| Added safe unwrap for `ifa_name` pointer | NetworkSampler.swift | Prevents null pointer crash on malformed kernel entries |

#### Menu Bar Indicator Fixes
| Fix | File | Impact |
|-----|------|--------|
| New `restoreStatusItem()` called after every activation policy toggle | App.swift | Re-applies `isVisible` and text after `.accessory` switch |
| Added `NSWorkspace.didWakeNotification` observer | App.swift | Restores status item after sleep/wake cycle |
| Defensive status item re-creation if button becomes nil | App.swift | Auto-recovers from system status bar resets |

#### Data Safety & Stability
| Fix | File | Impact |
|-----|------|--------|
| Force-flushes in-memory samples to SQLite at 9,500 entries | DashboardModel.swift | Prevents silent data loss (was dropping after 10K) |
| Fixed `flushPendingData` to also check `networkUsageDeltas` | DashboardModel.swift | Prevents network usage data loss on shutdown |
| Fixed stale `inMemorySamples` overwrite after `await` | DashboardModel.swift | Prevents concurrent modification data loss |
| Capped `safeDelta` overflow result at 10 GB | DashboardModel.swift | Prevents false 4.29 GB traffic spikes on interface reset |
| Added same-value guards to all `didSet` properties | DashboardModel.swift | Eliminates redundant heavy DB queries |
| Removed `.id(model.selectedRange)` from ScrollView | DashboardView.swift | Prevents livePulse animation freeze and scroll position loss |
| Fixed tooltip dismiss and Clear All Data to use `@MainActor` Tasks | DashboardView.swift | Prevents background-thread SwiftUI state mutation |

### v1.0.3 — Settings Tab & Clear All Data

* Dedicated Settings tab with launch-at-login, location permissions, and storage info.
* Complete "Clear All Data" reset with native confirmation dialog.
* SSID resolution fixes and text formatting crash fixes.

### v1.0.2 — App Sandbox & Accuracy

* Apple App Sandbox compliance with entitlements.
* 32-bit counter wrap-around fix for `getifaddrs`.
* Wi-Fi SSID resolution via CoreLocation + CoreWLAN.
* Automated test suite (`NetGaugeMacTestRunner`).

### v1.0.1 — Range-Aware Dashboard

* Detailed network stats with range-aware metrics.
* Active interfaces filtering.

### v1.0.0 — Initial Release

* Real-time menu bar speedometer.
* SQLite tiered retention strategy.
* Interactive bandwidth charts.

---

## Documentation

All audit reports, test scenarios, fix summaries, and version logs are tracked in the `Docs` directory:

- 📄 **netgauge_test_report.md**: Real-world test scenarios, identified issues, and verification results.
- 📜 **version_history.md**: Full version log tracking v1.0.0 through v1.0.4.
- 🛠️ **fix_summary.md**: Technical breakdown of mathematical correctness fixes and troubleshooting guide.

---

## Running Automated Accuracy Tests

To verify accuracy and feature functionality using the built-in test suite:

```bash
swift run NetGaugeMacTestRunner
```

This automated test suite verifies:
1. 32-bit kernel counter wrap-around calculation accuracy.
2. Multi-address network interface byte accumulation.
3. Usage bucket ID uniqueness for SwiftUI chart rendering.
4. Custom date range min/max start/end ordering.
5. Non-overlapping exclusive upper bound database queries.

---

## Build & Relaunch Instructions

To build the executable and sign with Apple App Sandbox entitlements:
```bash
# Compile Release Binary
swift build -c release

# Prepare NetGaugeMac.app Bundle contents
rm -rf NetGaugeMac.app
mkdir -p NetGaugeMac.app/Contents/MacOS NetGaugeMac.app/Contents/Resources
cp .build/release/NetGaugeMac NetGaugeMac.app/Contents/MacOS/NetGaugeMac
cp Sources/NetGaugeMac/AppIcon.png NetGaugeMac.app/Contents/Resources/AppIcon.png
cp Sources/NetGaugeMac/Info.plist NetGaugeMac.app/Contents/Info.plist

# Clean extended attributes and sign with App Sandbox Entitlements
xattr -cr NetGaugeMac.app
codesign -s - --entitlements Sources/NetGaugeMac/NetGaugeMac.entitlements --force --deep NetGaugeMac.app

# Update Applications folder installation
rm -rf /Applications/NetGaugeMac.app
cp -r NetGaugeMac.app /Applications/
touch /Applications/NetGaugeMac.app
xattr -cr /Applications/NetGaugeMac.app

# Relaunch App
killall NetGaugeMac || true
open /Applications/NetGaugeMac.app
```

To create the installer disk image:
```bash
bash build_dmg.sh
```

---

## Developer Credits

Designed and developed by: **Paritosh Chaudhari** (2026).
