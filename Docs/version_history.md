# NetGaugeMac — Version History & Changelog

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
