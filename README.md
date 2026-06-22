# NetGauge — Native macOS Real-time Traffic & Analytics Monitor

NetGauge is a native macOS utility application that tracks real-time network download and upload speeds directly in your Menu Bar and offers detailed bandwidth analytics inside a modern dashboard. 

The application is built on top of Apple's developer guidelines (HIG) using SwiftUI, Swift 6 strict concurrency, and raw `SQLite3` database persistence (zero-dependency).

---

## Key Features

* **Real-time Menu Bar Speedometer**: Displays stacked download (`↓`) and upload (`↑`) speeds dynamically in a monospaced font directly in the system status bar, updating every second.
* **Continuous Background Tracking**: Closing the dashboard window switches the application's activation policy to `.accessory` mode. The app continues network sampling silently in the background, keeping the Dock clean.
* **Modern Analytics Dashboard**: Includes hero cards (Today Total, Peak Hour, Quietest Hour), current-month charts, active interface bandwidth distribution, and range-based timelines (1D, Yesterday, 1M, 30D, and Custom).
* **SQLite Tiered Retention Strategy**:
  * **Raw samples (1/sec)**: Kept in memory only — never hits disk.
  * **Minute aggregation**: Every 60s, a single aggregated row is written to `network_minutes` (~1,440 rows/day).
  * **Hourly rollup (7 days)**: Minute rows older than 7 days are rolled up into `network_hours` (timezone-safe).
  * **Daily rollup (90 days)**: Hourly rows older than 90 days are rolled up into `network_days` and retained indefinitely, keeping database footprint minimal forever.
  * **WAL (Write-Ahead Logging)**: Enabled for crash-resilience. Single writer thread guaranteed via Swift actor isolation.
* **Auto-Start on Boot**: Modern login item registration (`SMAppService`) with a smart system uptime heuristic: if launched within 120 seconds of boot, it starts hidden in the Menu Bar automatically.
* **Drag-and-Drop Installation**: Distributed as a native installer disk image (`NetGaugeMac.dmg`).
* **High-Res App Icon & Developer Credits**: Dynamically loaded application icon with developer credits to **Paritosh Chaudhari**.

---

## Technical Details

- **Language**: Swift 5.10 / Swift 6
- **Frameworks**: SwiftUI, AppKit, Charts, ServiceManagement
- **Database**: SQLite3 (native libsqlite3 system library, zero-dependency)
- **Minimum OS**: macOS 14 Sonoma (uses modern `SMAppService` and Swift Charts APIs)

---

## File Structure

* [App.swift](file:///Users/paritoshchaudhari/Documents/Codex/2026-06-21/he/outputs/NetGaugeMac/Sources/NetGaugeMac/App.swift): Main application entry point, status menu item setup, multiline speed renderer, close button event interception, custom About panel, and boot startup heuristics.
* [DashboardModel.swift](file:///Users/paritoshchaudhari/Documents/Codex/2026-06-21/he/outputs/NetGaugeMac/Sources/NetGaugeMac/DashboardModel.swift): `@MainActor` state manager, 1-second capture loop, in-memory buffer, and `SMAppService` toggle bindings.
* [DashboardView.swift](file:///Users/paritoshchaudhari/Documents/Codex/2026-06-21/he/outputs/NetGaugeMac/Sources/NetGaugeMac/DashboardView.swift): SwiftUI dashboard view, custom design system tokens, 45-degree rotated X-axis labels, and active interfaces load panel.
* [UsageStore.swift](file:///Users/paritoshchaudhari/Documents/Codex/2026-06-21/he/outputs/NetGaugeMac/Sources/NetGaugeMac/UsageStore.swift): Serial actor-isolated raw `sqlite3` database engine, timezone-aligned rollup jobs, and unaligned timestamp boundary query alignment.
* [NetworkSampler.swift](file:///Users/paritoshchaudhari/Documents/Codex/2026-06-21/he/outputs/NetGaugeMac/Sources/NetGaugeMac/NetworkSampler.swift): Stateless network byte counters queried from Kernel BSD `getifaddrs` API.

---

## Build & Relaunch Instructions

To build the executable and resource bundle locally:
```bash
# Compile Release Binary
swift build -c release

# Update NetGaugeMac.app Bundle contents
cp .build/release/NetGaugeMac NetGaugeMac.app/Contents/MacOS/NetGaugeMac
cp -r .build/release/NetGaugeMac_NetGaugeMac.bundle NetGaugeMac.app/Contents/Resources/
cp Sources/NetGaugeMac/AppIcon.png NetGaugeMac.app/Contents/Resources/AppIcon.png

# Update Applications folder installation
rm -rf /Applications/NetGaugeMac.app
cp -r NetGaugeMac.app /Applications/
touch /Applications/NetGaugeMac.app

# Relaunch App
killall NetGaugeMac || true
open /Applications/NetGaugeMac.app
```

To create the installer disk image:
```bash
rm -f NetGaugeMac.dmg
rm -rf dmg_temp
mkdir -p dmg_temp
cp -r NetGaugeMac.app dmg_temp/
ln -s /Applications dmg_temp/Applications
hdiutil create -volname "NetGaugeMac" -srcfolder dmg_temp -ov -format UDZO NetGaugeMac.dmg
rm -rf dmg_temp
```

---

## Developer Credits

Designed and developed by: **Paritosh Chaudhari** (2026).
