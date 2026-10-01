# NetGaugeMac — Version History & Changelog

## [1.0.6] - 2026-10-01

### Added
- **CrashGuard Pre-Launch Protection**: Installed signal handlers (`SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`) and `NSSetUncaughtExceptionHandler` to log and persist structured crash reports to disk before re-raising.
- **Unified App Logging (`AppLogger`)**: Centralized `os.Logger` facade across 5 categories (`app`, `network`, `store`, `ui`, `lifecycle`) and atomic `crash_context.json` generation on fatal events.
- **Instruments Signpost Profiling (`NGSignposter`)**: Integrated signpost intervals on network capture loops for Instruments performance tracing.
- **Diagnostics & Logs UI in Settings**: Added diagnostics card in Settings featuring direct Console.app launcher, interactive Crash Reports viewer with stack traces, and "Copy Diagnostic Report" clipboard exporter.
- **Custom Entry Point (`NetGaugeMacMain`)**: Bootstrapped early process lifecycle to ensure crash traps and fault inspection run prior to AppKit/SwiftUI runtime initialization.

### Fixed
- **SQLite Database Corruption Auto-Recovery**: Added `PRAGMA integrity_check;` validation on launch; automatically quarantines corrupt databases (`netgauge.db.corrupt.<ts>`) along with WAL/SHM sidecars to prevent startup crash loops.
- **Database Connection Retries**: Added retry with backoff for transient early-boot file locks in `DashboardModel.start()`.
- **Startup Timeout Guard**: Enforced a 10-second timeout on `model.start()` in `AppDelegate` to prevent hangs caused by filesystem stalls.
- **SQLite Performance & Safety PRAGMAs**: Configured `PRAGMA synchronous=NORMAL;` and `PRAGMA foreign_keys=ON;`.
- **Silent Failure Logging**: Replaced silent try? blocks with detailed categorized logging across `UsageStore`, `DashboardModel`, and `NetworkSampler`.

---

## [1.0.5] - 2026-08-06

### Fixed
- **Startup Spin Loop**: `captureTask` now only starts after `UsageStore` initialization succeeds.
- **Window Close Dangling Pointer**: `isReleasedWhenClosed = false` initialized immediately after `NSWindow` allocation.
- **Graceful Termination Lockup**: Added hard 3-second timeout to `flushPendingData` in `applicationShouldTerminate`.
- **Status Item Re-creation Race**: Managed delayed status item updates via a single cancellable `DispatchWorkItem`.
- **Duplicate Menu Bar Item**: Removed redundant `setupStatusItem()` call inside text update routines.
- **Background Battery Drain**: Added `windowIsVisible` flag slowing polling interval to 2s and suspending chart event queries when hidden.
- **O(N) Event Refresh**: Rewrote `refreshEvents()` into a single O(N) pass over samples instead of 7 redundant filter passes.
- **UI Label Allocations**: Cached `ByteCountFormatter` statically to avoid per-frame allocations during chart rendering.
- **Unnecessary GPS Hardware Power**: Removed `manager.requestLocation()` call on startup.
- **Main Thread UI Stalls**: Offloaded Wi-Fi/SystemConfiguration network name lookups to `Task.detached(priority: .utility)`.

---

## [1.0.4] - 2026-08-06

### Fixed
- **SQLite Concurrency**: Switched SQLite flags to `SQLITE_OPEN_FULLMUTEX` to prevent corruption under actor reentrancy.
- **Integer Overflow**: Clamped UInt64 to Int64 conversions with `Int64(clamping:)`.
- **Kernel Interface Flag Crash**: Converted `ifa_flags` comparisons to `UInt32` to avoid signed overflow traps.
- **Kernel Memory Safety**: Added null-check guard for `ifa_name` pointer unwrap.
- **Sleep/Wake Status Recovery**: Added `NSWorkspace.didWakeNotification` observer to restore status bar icon after sleep.
- **Data Truncation Safety**: Lowered memory buffer force-flush threshold to 9,500 entries (avoiding 10,000-entry drop).

---

## [1.0.3] - 2026-07-29

### Added
- **Settings Tab**: Added a dedicated Settings tab accessible via top navigation bar or status bar menu (`Settings...` / `Cmd+,`).
- **Clear All Data Feature**: Introduced a data reset action in Settings that truncates all SQLite tables (`network_minutes`, `network_hours`, `network_days`, `network_usage`), clears in-memory buffers, resets kernel sampling baselines, and presents a native macOS confirmation warning dialog.
- **SSID Caching**: Added 30-second per-interface SSID caching to eliminate per-second `CoreWLAN` / `SystemConfiguration` IPC query overhead.
- **Graceful Shutdown Data Flushing**: Wired `flushPendingData()` into `applicationShouldTerminate` (`.terminateLater`) to guarantee no sub-minute traffic data is lost when quitting.

### Fixed
- **macOS 26 SwiftUI Format String Crash**: Replaced dynamic `Text()` interpolations with `Text(verbatim:)` across all components (`HeroMetric`, `RateTile`, `MiniStatCard`, `InterfaceRateRow`, `NetworkUsageRow`, `ChartTooltipCard`, `TooltipRow`, and date footers) to prevent `LocalizedStringKey` null-pointer crashes.
- **macOS Location Authorization API**: Replaced iOS-only `requestAlwaysAuthorization()` with `requestWhenInUseAuthorization()` and removed macOS-unavailable `authorizedWhenInUse` case.
- **WiFi Interface Disambiguation**: Added `"Wi-Fi (interfaceName)"` fallback so distinct physical adapters remain separate database rows even if location access is unavailable.
- **Today Stats Rollup Bug**: Fixed `loadNetworkUsages()` today query by using `UNION ALL` across `network_minutes`, `network_hours`, and `network_days` to prevent metrics from disappearing after rollups.
- **Double/UInt64 Overflow Safety**: Added `isFinite` and `Int64.max` clamping to `speedString` and `byteString` formatters to prevent numeric overflow crashes.

---

## [1.0.2] - 2026-07-29

### Added
- **Apple App Sandbox**: Integrated `com.apple.security.app-sandbox` entitlement with Network Client, Network Server, Location, and User Selected File privileges.
- **Container Database Migration**: Automatic migration of legacy unsandboxed SQLite databases (`netgauge.db`, `-wal`, `-shm`) into `~/Library/Containers/com.paritoshchaudhari.NetGaugeMac/Data/Library/Application Support/NetGaugeMac/`.
- **Automated Feature Accuracy Test Runner**: Added `NetGaugeMacTestRunner` target verifying counter wrap, tier boundaries, and interface accumulation.
- **Enhanced Wi-Fi SSID Resolution**: Improved SSID detection logic across CoreWLAN interfaces (`CWInterface`) and SystemConfiguration display names containing `"Wi-Fi"`.

### Fixed
- **Wi-Fi Network Name Resolution**: Fixed issue where display names like `"Wi-Fi / Ethernet (en0)"` fell back to generic `"Wi-Fi"` label instead of resolving SSID.
- **32-Bit Counter Overflow**: Resolved ~3-30% traffic underreporting by calculating exact 32-bit wrap deltas.
- **Data Double-Counting**: Fixed overlapping inclusive bounds (`<=`) in `loadTotals` and `loadEvents` by enforcing exclusive upper bounds (`<`).
- **Missing Month Totals**: Included `network_days` table in `loadNetworkUsages` month statistics query.
- **Tooltip Arrows**: Swapped tooltip arrow icons so Download displays `▼` and Upload displays `▲`.
- **Tooltip Dismissal Race**: Cancelled active dismiss tasks when hovering over new chart buckets.
- **macOS CoreLocation Compatibility**: Resolved `CLAuthorizationStatus.authorizedWhenInUse` compilation error on macOS by using `.authorizedAlways` and `.authorized`.

---

## [1.0.1] - 2026-07-29

### Added
- Developer attribution for **Paritosh Chaudhari** across About Panel, `Info.plist`, and documentation.
- Window frame autosave persistence (`setFrameAutosaveName("NetGaugeDashboard")`).
- Dynamic bundle versioning in About Panel.

### Fixed
- Debounced refresh cycles and optimized SQLite statement reuse (`stmt.reset()`) during hourly and daily rollups.
- Added `sqlite3_busy_timeout` to handle concurrent multi-threaded database locks.

---

## [1.0.0] - 2026-07-21

### Added
- Initial release of NetGaugeMac real-time menu-bar traffic monitor.
- SwiftUI dashboard with stacked Hero metrics, live rate strip, interactive charts, active interfaces view, and tiered SQLite persistence.
