#!/usr/bin/env bash
# ============================================================
#  NetGaugeMac — Professional DMG Builder (v3 — Final)
#  • Custom background image
#  • Volume .icns icon (derived from AppIcon.png via sips+iconutil)
#  • Applications symlink for drag-to-install
#  • UDZO zlib-9 compression
#  • Works without Finder automation or AppleScript
# ============================================================

set -euo pipefail

# ── Config ───────────────────────────────────────────────────
APP_BUNDLE="NetGaugeMac.app"
DMG_NAME="NetGaugeMac"
VERSION="1.0.0"
OUTPUT_DMG="${DMG_NAME}.dmg"
TMP_DMG="${DMG_NAME}-tmp.dmg"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/${APP_BUNDLE}"
BG_IMAGE="${SCRIPT_DIR}/dmg_background.jpg"
ICON_SRC="${SCRIPT_DIR}/Sources/NetGaugeMac/AppIcon.png"

STAGING_DIR="${SCRIPT_DIR}/.dmg_staging"
MOUNT_PATH="/Volumes/${DMG_NAME}"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
step()  { echo -e "${CYAN}▶${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
die()   { echo -e "${RED}✗${NC} $1" >&2; exit 1; }

# ── Banner ───────────────────────────────────────────────────
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   NetGaugeMac DMG Builder  v${VERSION}    ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── Pre-flight ───────────────────────────────────────────────
step "Checking prerequisites..."
[[ -d "${APP_PATH}" ]] || die "App bundle not found: ${APP_PATH}"
ok "App bundle: ${APP_PATH}"

# ── Clean ────────────────────────────────────────────────────
step "Cleaning previous build..."
rm -rf "${STAGING_DIR}"
rm -f  "${SCRIPT_DIR}/${TMP_DMG}" "${SCRIPT_DIR}/${OUTPUT_DMG}"
if hdiutil info 2>/dev/null | grep -q "${MOUNT_PATH}"; then
    hdiutil detach "${MOUNT_PATH}" -force -quiet 2>/dev/null || true
fi
ok "Clean"

# ── Build .icns volume icon ──────────────────────────────────
ICNS_FILE=""
step "Building volume icon..."
if [[ -f "${ICON_SRC}" ]]; then
    ICONSET_TMP=$(mktemp -d)
    ICONSET="${ICONSET_TMP}/NetGauge.iconset"
    mkdir -p "${ICONSET}"
    sips -z 16   16   "${ICON_SRC}" --out "${ICONSET}/icon_16x16.png"      -s format png 2>/dev/null
    sips -z 32   32   "${ICON_SRC}" --out "${ICONSET}/icon_16x16@2x.png"   -s format png 2>/dev/null
    sips -z 32   32   "${ICON_SRC}" --out "${ICONSET}/icon_32x32.png"      -s format png 2>/dev/null
    sips -z 64   64   "${ICON_SRC}" --out "${ICONSET}/icon_32x32@2x.png"   -s format png 2>/dev/null
    sips -z 128  128  "${ICON_SRC}" --out "${ICONSET}/icon_128x128.png"    -s format png 2>/dev/null
    sips -z 256  256  "${ICON_SRC}" --out "${ICONSET}/icon_128x128@2x.png" -s format png 2>/dev/null
    sips -z 256  256  "${ICON_SRC}" --out "${ICONSET}/icon_256x256.png"    -s format png 2>/dev/null
    sips -z 512  512  "${ICON_SRC}" --out "${ICONSET}/icon_256x256@2x.png" -s format png 2>/dev/null
    sips -z 512  512  "${ICON_SRC}" --out "${ICONSET}/icon_512x512.png"    -s format png 2>/dev/null
    sips -z 1024 1024 "${ICON_SRC}" --out "${ICONSET}/icon_512x512@2x.png" -s format png 2>/dev/null
    ICNS_FILE="${ICONSET_TMP}/NetGauge.icns"
    iconutil -c icns "${ICONSET}" -o "${ICNS_FILE}" 2>/dev/null && ok "Volume icon created (1.8 MB .icns)" || { warn "iconutil failed; no volume icon"; ICNS_FILE=""; }
else
    warn "AppIcon.png not found; no volume icon"
fi

# ── Staging area ─────────────────────────────────────────────
step "Preparing staging area..."
mkdir -p "${STAGING_DIR}/.background"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
[[ -f "${BG_IMAGE}" ]] && cp "${BG_IMAGE}" "${STAGING_DIR}/.background/background.jpg"
ln -s /Applications "${STAGING_DIR}/Applications"
ok "Staging ready"

# ── Calculate DMG size ───────────────────────────────────────
step "Calculating DMG size..."
APP_SIZE_KB=$(du -sk "${APP_PATH}" | awk '{print $1}')
EXTRA_KB=$(( 22 * 1024 ))
DMG_SIZE_MB=$(( (APP_SIZE_KB + EXTRA_KB + 1023) / 1024 ))
ok "DMG size: ~${DMG_SIZE_MB} MB"

# ── Create writable temp DMG ─────────────────────────────────
step "Creating writable temp DMG..."
hdiutil create \
    -srcfolder "${STAGING_DIR}" \
    -volname "${DMG_NAME}" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,b=16" \
    -format UDRW \
    -size "${DMG_SIZE_MB}m" \
    "${SCRIPT_DIR}/${TMP_DMG}" \
    -quiet
ok "Temp DMG created"

# ── Mount ────────────────────────────────────────────────────
step "Mounting temp DMG..."
hdiutil attach \
    -readwrite -noverify -noautoopen \
    "${SCRIPT_DIR}/${TMP_DMG}" \
    -quiet
ok "Mounted: ${MOUNT_PATH}"
sleep 1

# ── Set volume icon ──────────────────────────────────────────
if [[ -n "${ICNS_FILE}" && -f "${ICNS_FILE}" ]]; then
    cp "${ICNS_FILE}" "${MOUNT_PATH}/.VolumeIcon.icns"
    SetFile -a C "${MOUNT_PATH}" 2>/dev/null && ok "Volume icon applied" || warn "SetFile unavailable; icon may not show on mount"
fi

# ── Hide dot-folders ─────────────────────────────────────────
chflags hidden "${MOUNT_PATH}/.background" 2>/dev/null || true

# ── Sync ─────────────────────────────────────────────────────
sync

# ── Unmount ──────────────────────────────────────────────────
step "Unmounting..."
hdiutil detach "${MOUNT_PATH}" -quiet
ok "Unmounted"

# ── Compress to read-only UDZO ───────────────────────────────
step "Compressing to final DMG (UDZO zlib-9)..."
hdiutil convert \
    "${SCRIPT_DIR}/${TMP_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${SCRIPT_DIR}/${OUTPUT_DMG}" \
    -quiet
ok "Compressed"

# ── Cleanup ──────────────────────────────────────────────────
step "Cleaning up..."
rm -f  "${SCRIPT_DIR}/${TMP_DMG}"
rm -rf "${STAGING_DIR}"
[[ -n "${ICNS_FILE}" ]] && rm -rf "$(dirname "${ICNS_FILE}")" 2>/dev/null || true
ok "Cleaned"

# ── Summary ──────────────────────────────────────────────────
FINAL_SIZE=$(du -sh "${SCRIPT_DIR}/${OUTPUT_DMG}" | awk '{print $1}')
echo ""
echo -e "${GREEN}${BOLD}  ✅ DMG created successfully!${NC}"
echo -e "${BOLD}  📦 File:  ${NC}${OUTPUT_DMG}"
echo -e "${BOLD}  📏 Size:  ${NC}${FINAL_SIZE}"
echo -e "${BOLD}  📍 Path:  ${NC}${SCRIPT_DIR}/${OUTPUT_DMG}"
echo ""
