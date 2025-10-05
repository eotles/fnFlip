#!/usr/bin/env zsh
set -euo pipefail

echo "== autodetecting app, bundle id, team id, and notary profile =="

# 1) Locate the .app
APP_ARG="${1:-}"
if [[ -n "$APP_ARG" && -d "$APP_ARG" && "$APP_ARG" == *.app ]]; then
  APP="$APP_ARG"
else
  DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
  APP=$(ls -t $DERIVED/*/Build/Products/Release/*.app 2>/dev/null | head -n 1 | tr -d '\n' || true)
  if [[ -z "${APP:-}" ]]; then
    APP=$(ls -t "$PWD"/*.app 2>/dev/null | head -n 1 | tr -d '\n' || true)
  fi
fi

if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
  echo "Could not find a .app. Pass one explicitly, for example:"
  echo "  zsh $0 /path/to/YourApp.app"
  exit 1
fi
APP="$(cd "$APP"; pwd)"
APP_DIR="$(dirname "$APP")"

# 2) Read Info.plist for app name and bundle id
INFO_PLIST="$APP/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found at $INFO_PLIST"
  exit 1
fi

read_plist_key() {
  local key="$1"
  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null || true
  else
    /usr/bin/defaults read "${INFO_PLIST%*.plist}" "$key" 2>/dev/null || true
  fi
}

APP_NAME="$(read_plist_key CFBundleDisplayName)"
[[ -z "$APP_NAME" ]] && APP_NAME="$(read_plist_key CFBundleName)"
[[ -z "$APP_NAME" ]] && APP_NAME="$(basename "$APP" .app)"
BUNDLE_ID="$(read_plist_key CFBundleIdentifier)"

if [[ -z "$BUNDLE_ID" ]]; then
  echo "Could not read CFBundleIdentifier from Info.plist"
  exit 1
fi

# 3) Extract Team ID from existing code signature, if any
TEAM_ID="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | awk -F= '/TeamIdentifier/ {print $2; exit}')"
if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(/usr/bin/codesign -d -r- "$APP" 2>&1 | sed -n 's/.*team-identifier \"\(.*\)\".*/\1/p' | head -n1)"
fi

# 4) Choose a notarytool profile if present
NOTARY_PROFILE=""
if command -v xcrun >/dev/null 2>&1; then
  PROFILES_JSON="$(xcrun notarytool list-profiles 2>/dev/null || true)"
  if [[ -n "$PROFILES_JSON" ]]; then
    NOTARY_PROFILE="$(echo "$PROFILES_JSON" | awk -F'"' '/"name":/ {print $4; exit}')"
  fi
fi

echo "App: $APP"
echo "Name: $APP_NAME"
echo "Bundle ID: $BUNDLE_ID"
[[ -n "$TEAM_ID" ]] && echo "Team ID: $TEAM_ID" || echo "Team ID: not detected (app may not be signed yet)"
[[ -n "$NOTARY_PROFILE" ]] && echo "Notary profile: $NOTARY_PROFILE" || echo "Notary profile: none detected"

# 5) Output paths in the same folder as the app
VOLNAME="$APP_NAME"

# Unique DMG path helper to avoid clobbering existing files
unique_path() {
  local base="$1"
  local ext="$2"
  local path="${base}.${ext}"
  local i=1
  while [[ -e "$path" ]]; do
    path="${base} (${i}).${ext}"
    ((i++))
  done
  echo "$path"
}

DMG_PATH="$(unique_path "$APP_DIR/$APP_NAME" "dmg")"

# 6) Verify signing state for info
echo "Verifying code signature on app (informational)"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP" || true
/usr/sbin/spctl -a -vv "$APP" || true

# 7) Build DMG next to the app
echo "Creating DMG at: $DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
  # create-dmg writes temp files into the destination directory
  create-dmg \
    --volname "$VOLNAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 120 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 430 200 \
    --icon "${APP_NAME}.app" 170 200 \
    "$DMG_PATH" \
    "$APP"
else
  echo "create-dmg not found, falling back to hdiutil"
  TMP_DMG="$APP_DIR/.tmp_${APP_NAME}.dmg"
  rm -f "$TMP_DMG"
  hdiutil create -volname "$VOLNAME" -srcfolder "$APP" -ov -format UDRW "$TMP_DMG"
  hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_PATH"
  rm -f "$TMP_DMG"
fi

# 8) Notarize
echo "Submitting DMG for notarization"
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  read -r "APPLE_ID?Apple ID email: "
  read -r "TEAM_ID_IN?Team ID (press Enter to use detected: $TEAM_ID): "
  TEAM_ID_FINAL="${TEAM_ID_IN:-$TEAM_ID}"
  if [[ -z "$TEAM_ID_FINAL" ]]; then
    echo "Team ID is required when no notary profile is configured."
    exit 1
  fi
  echo "You will be prompted for your app-specific password in the system prompt."
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID_FINAL" \
    --wait
fi

# 9) Staple and validate
echo "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH" || { echo "Staple failed"; exit 1; }
xcrun stapler validate "$DMG_PATH" || true
/usr/sbin/spctl -a -vv "$DMG_PATH" || true

echo
echo "All set. DMG is ready next to your app:"
echo "  $DMG_PATH"
