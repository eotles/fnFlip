#!/usr/bin/env bash
# Tools/autopackage.sh
# Signed, notarized .pkg for fnFlip.app.
# Lets users choose "all users" (default) or "me only". Branded UI, launches once.

set -euo pipefail

### =========
### CONFIG
### =========
APP_NAME="fnFlip.app"
APP_SOURCE_PATH="${APP_SOURCE_PATH:-$(pwd)/${APP_NAME}}"
PKG_ID="com.eotles.fnflip"
VERSION="${VERSION:-1.2}"

# We stage "Applications/fnFlip.app" under a fake root.
# With a staged root, install-location must be "/" to land at /Applications.
INSTALL_LOCATION="/"

OUT_DIR="${OUT_DIR:-$(pwd)}"
WORK_DIR="$(mktemp -d /tmp/fnflip_pkg.XXXXXX)"
PKGROOT="${WORK_DIR}/pkgroot"
SCRIPTS_DIR="${WORK_DIR}/scripts"
RESOURCES_DIR="${WORK_DIR}/resources"
PKG_DIR="${WORK_DIR}/pkgs"
COMP_PLIST="${WORK_DIR}/component.plist"
COMPONENT_PKG="${PKG_DIR}/fnFlip-component.pkg"
UNSIGNED_PKG="${WORK_DIR}/fnFlip-unsigned.pkg"
OUT_PKG="${OUT_DIR}/fnFlip-${VERSION}.pkg"
DIST_XML="${WORK_DIR}/distribution.xml"

TEAM_ID="${TEAM_ID:-YOURTEAMID}"
DEVELOPER_ID_INSTALLER="${DEVELOPER_ID_INSTALLER:-}"   # Common Name or SHA-1
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-password}"
APPLE_ID="${APPLE_ID:-}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-}"               # optional single PNG override

### =========
### TOOL DISCOVERY
### =========
find_or_die() {
  local name="$1"
  local path; path="$(/usr/bin/xcrun --find "$name" 2>/dev/null || true)"
  [[ -z "$path" || ! -x "$path" ]] && path="$(command -v "$name" || true)"
  if [[ -z "$path" || ! -x "$path" ]]; then
    echo "Missing tool: $name" >&2
    echo "Install Command Line Tools: xcode-select --install" >&2
    exit 1
  fi
  printf "%s" "$path"
}
PKGBUILD_BIN="$(find_or_die pkgbuild)"
PRODUCTBUILD_BIN="$(find_or_die productbuild)"
PRODUCTSIGN_BIN="$(find_or_die productsign)"
STAPLER_BIN="$(find_or_die stapler)"
PLISTBUDDY_BIN="/usr/libexec/PlistBuddy"
SIPS_BIN="$(command -v sips || true)"

### =========
### PRECHECKS
### =========
[[ -z "$DEVELOPER_ID_INSTALLER" ]] && { echo "Set DEVELOPER_ID_INSTALLER."; exit 1; }
[[ ! -d "$APP_SOURCE_PATH" || ! -f "$APP_SOURCE_PATH/Contents/Info.plist" ]] && { echo "App not found at $APP_SOURCE_PATH"; exit 1; }

echo "Building installer for: $APP_SOURCE_PATH"
echo "Output pkg will be:    $OUT_PKG"

mkdir -p "$PKGROOT/Applications" "$SCRIPTS_DIR" "$RESOURCES_DIR" "$PKG_DIR"

### =========
### STAGE PAYLOAD & COMPONENT PLIST (allow both user/system)
### =========
# Stage to a fake root so --analyze/--root works
rsync -a "$APP_SOURCE_PATH" "$PKGROOT/Applications/"

# Analyze component, then:
# - remove InstallOnlyForCurrentUser (so both options are allowed)
# - make the bundle relocatable (so ~/Applications is valid)
# - keep strict id + version check
"$PKGBUILD_BIN" --analyze --root "$PKGROOT" "$COMP_PLIST" >/dev/null

$PLISTBUDDY_BIN -c "Delete :InstallOnlyForCurrentUser" "$COMP_PLIST" 2>/dev/null || true
$PLISTBUDDY_BIN -c "Delete :0:InstallOnlyForCurrentUser" "$COMP_PLIST" 2>/dev/null || true

$PLISTBUDDY_BIN -c "Set :BundleIsRelocatable true" "$COMP_PLIST" 2>/dev/null || \
$PLISTBUDDY_BIN -c "Set :0:BundleIsRelocatable true" "$COMP_PLIST" 2>/dev/null || true

$PLISTBUDDY_BIN -c "Set :BundleHasStrictIdentifier true" "$COMP_PLIST" 2>/dev/null || \
$PLISTBUDDY_BIN -c "Set :0:BundleHasStrictIdentifier true" "$COMP_PLIST" 2>/dev/null || true

$PLISTBUDDY_BIN -c "Set :BundleIsVersionChecked true" "$COMP_PLIST" 2>/dev/null || \
$PLISTBUDDY_BIN -c "Set :0:BundleIsVersionChecked true" "$COMP_PLIST" 2>/dev/null || true

echo "[component] component.plist preview:"
/usr/bin/plutil -p "$COMP_PLIST" 2>/dev/null | head -n 30 || true

### =========
### BACKGROUND SELECTION (Light + Dark, bottom-left)
### =========
BG_XML=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BG_LIGHT_SRC=""
BG_DARK_SRC=""

# explicit single-image override
if [[ -n "$BACKGROUND_IMAGE" && -f "$BACKGROUND_IMAGE" ]]; then
  cp "$BACKGROUND_IMAGE" "${RESOURCES_DIR}/background.png"
  echo "[installer] Using single background: $BACKGROUND_IMAGE"
fi

# look for generated pair
if [[ ! -f "${RESOURCES_DIR}/background.png" ]]; then
  for base in \
    "$PWD/InstallerBackgrounds" \
    "$PWD/Tools/InstallerBackgrounds" \
    "$SCRIPT_DIR/InstallerBackgrounds"; do
    [[ -z "$BG_LIGHT_SRC" && -f "$base/fnflip-installer-light.png" ]] && BG_LIGHT_SRC="$base/fnflip-installer-light.png"
    [[ -z "$BG_DARK_SRC"  && -f "$base/fnflip-installer-dark.png"  ]] && BG_DARK_SRC="$base/fnflip-installer-dark.png"
  done
  [[ -n "$BG_LIGHT_SRC" ]] && { cp "$BG_LIGHT_SRC" "${RESOURCES_DIR}/background-light.png"; echo "[installer] Found light background: $BG_LIGHT_SRC"; }
  [[ -n "$BG_DARK_SRC"  ]] && { cp "$BG_DARK_SRC"  "${RESOURCES_DIR}/background-dark.png";  echo "[installer] Found dark background:  $BG_DARK_SRC"; }
fi

# fallback from .icns
if [[ ! -f "${RESOURCES_DIR}/background.png" && ! -f "${RESOURCES_DIR}/background-light.png" && -n "$SIPS_BIN" ]]; then
  ICON_ICNS="$($PLISTBUDDY_BIN -c 'Print :CFBundleIconFile' "$APP_SOURCE_PATH/Contents/Info.plist" 2>/dev/null || true)"
  [[ -n "$ICON_ICNS" && "${ICON_ICNS##*.}" != "icns" ]] && ICON_ICNS="${ICON_ICNS}.icns"
  ICON_PATH="${APP_SOURCE_PATH}/Contents/Resources/${ICON_ICNS:-}"
  [[ -z "$ICON_ICNS" ]] && ICON_PATH="$(/bin/ls "$APP_SOURCE_PATH/Contents/Resources/"*.icns 2>/dev/null | head -n1 || true)"
  if [[ -f "$ICON_PATH" ]] && "$SIPS_BIN" -s format png "$ICON_PATH" --out "${RESOURCES_DIR}/background.png" >/dev/null 2>&1; then
    echo "[installer] Converted app .icns for background: $ICON_PATH"
  fi
fi

# Background XML (bottom-left to avoid content panel)
if [[ -f "${RESOURCES_DIR}/background-light.png" && -f "${RESOURCES_DIR}/background-dark.png" ]]; then
  BG_XML='  <background file="background-light.png" alignment="bottomleft" scaling="tofit"/>
  <background-darkAqua file="background-dark.png" alignment="bottomleft" scaling="tofit"/>'
elif [[ -f "${RESOURCES_DIR}/background.png" ]]; then
  BG_XML='  <background file="background.png" alignment="bottomleft" scaling="tofit"/>'
fi

### =========
### INSTALLER SCRIPTS
### =========
cat > "${SCRIPTS_DIR}/preinstall" <<'EOSH'
#!/bin/bash
set -euo pipefail
exit 0
EOSH
chmod 755 "${SCRIPTS_DIR}/preinstall"

# Launch from the chosen location.
# If running as root (all users), resolve the console user's home and open in their session.
cat > "${SCRIPTS_DIR}/postinstall" <<'EOSH'
#!/bin/bash
set -euo pipefail

APP_SYSTEM_PATH="/Applications/fnFlip.app"

console_user() { /usr/bin/stat -f%Su /dev/console; }
user_home() { /usr/bin/dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '{print $2}'; }
user_uid() { /usr/bin/id -u "$1"; }

if [[ "$(id -u)" -eq 0 ]]; then
  CU="$(console_user)"
  [[ -z "$CU" || "$CU" == "root" ]] && exit 0
  CU_HOME="$(user_home "$CU")"
  TARGET_APP="$APP_SYSTEM_PATH"
  if [[ -n "$CU_HOME" && -d "$CU_HOME/Applications/fnFlip.app" ]]; then
    TARGET_APP="$CU_HOME/Applications/fnFlip.app"
  fi
  /bin/sleep 1
  /bin/launchctl asuser "$(user_uid "$CU")" /usr/bin/open -a "$TARGET_APP" 2>/dev/null || true
else
  APP_USER_PATH="${HOME}/Applications/fnFlip.app"
  TARGET_APP="$APP_USER_PATH"
  [[ -d "$APP_USER_PATH" ]] || TARGET_APP="$APP_SYSTEM_PATH"
  /bin/sleep 1
  /usr/bin/open -a "$TARGET_APP" 2>/dev/null || true
fi

exit 0
EOSH
chmod 755 "${SCRIPTS_DIR}/postinstall"

### =========
### WELCOME / CONCLUSION
### =========
# NOTE: Use \ansi\uc0 and RTF Unicode escapes for symbols: ⌘(U+2318)=\u8984, ⌥(U+2325)=\u8997
cat > "${RESOURCES_DIR}/Welcome.rtf" <<'EORTF'
{\rtf1\ansi\uc0\deff0
\b Install fnFlip\b0\line
\line
fnFlip is a tiny macOS menu bar app to switch between hardware/media keys and standard function keys.\line
\line
Choose where to install: \b all users (recommended) \b0 or \b me only \b0.\line
\line
Either way, fnFlip will launch once after install and will continue launching at login. You may turn off the Launch at Login setting at any time.
}
EORTF

cat > "${RESOURCES_DIR}/Conclusion.rtf" <<'EORTF'
{\rtf1\ansi\uc0\deff0
\b fnFlip is installed\b0\line
\line
fnFlip should now be running. You can find it in the menu bar and in your Applications folder.\line
\line
You can change the behavior of macOS function keys by clicking the icon in the menu bar or by using the hotkey shortcut: \u8984 \u8997 F (Command, Option, F).\line
\line
You can close this window.
}
EORTF

### =========
### BUILD COMPONENT PKG (from staged root + component plist)
### =========
"$PKGBUILD_BIN" \
  --identifier "${PKG_ID}" \
  --version "${VERSION}" \
  --root "$PKGROOT" \
  --component-plist "$COMP_PLIST" \
  --install-location "${INSTALL_LOCATION}" \
  --scripts "${SCRIPTS_DIR}" \
  "${COMPONENT_PKG}"

### =========
### DISTRIBUTION XML (enable both domains; default visually selects All Users)
### =========
cat > "$DIST_XML" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>fnFlip</title>
${BG_XML}
  <welcome file="Welcome.rtf"/>
  <conclusion file="Conclusion.rtf"/>
  <options customize="never" require-scripts="true"/>
  <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="true"/>
  <choices-outline>
    <line choice="default">
      <line choice="fnflip_choice"/>
    </line>
  </choices-outline>
  <choice id="default"/>
  <choice id="fnflip_choice" title="fnFlip" selected="true">
    <pkg-ref id="${PKG_ID}"/>
  </choice>
  <pkg-ref id="${PKG_ID}" version="${VERSION}">${COMPONENT_PKG}</pkg-ref>
</installer-gui-script>
EOF

### =========
### WRAP, SIGN, NOTARIZE, STAPLE
### =========
"$PRODUCTBUILD_BIN" \
  --distribution "$DIST_XML" \
  --resources "${RESOURCES_DIR}" \
  --package-path "${PKG_DIR}" \
  "${UNSIGNED_PKG}"

"$PRODUCTSIGN_BIN" --sign "${DEVELOPER_ID_INSTALLER}" "${UNSIGNED_PKG}" "${OUT_PKG}"
echo "Signed pkg at: ${OUT_PKG}"

if [[ -n "${NOTARY_PROFILE}" ]]; then
  /usr/bin/xcrun notarytool submit "${OUT_PKG}" --keychain-profile "${NOTARY_PROFILE}" --wait
else
  [[ -z "${APPLE_ID}" || -z "${APP_SPECIFIC_PASSWORD}" || -z "${TEAM_ID}" ]] && { echo "Provide notarization credentials or NOTARY_PROFILE."; exit 1; }
  /usr/bin/xcrun notarytool submit "${OUT_PKG}" --apple-id "${APPLE_ID}" --team-id "${TEAM_ID}" --password "${APP_SPECIFIC_PASSWORD}" --wait
fi

"$STAPLER_BIN" staple "${OUT_PKG}"
/usr/sbin/spctl --assess --type install --verbose "${OUT_PKG}" || true

echo
echo "Done. Installer at: ${OUT_PKG}"
echo "Unicode hotkey renders correctly via RTF escapes."
echo

rm -rf "${WORK_DIR}"
