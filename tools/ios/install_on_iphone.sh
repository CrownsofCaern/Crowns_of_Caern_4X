#!/usr/bin/env bash
# Builds the current checkout for iOS and installs it on a USB-connected iPhone (macOS only).
#
#   tools/ios/install_on_iphone.sh
#
# Per-Mac settings live outside the repo in ~/.crowns_of_cinder_ios (shell syntax):
#   TEAM_ID=ABCDE12345                         # Xcode > Settings > Accounts (Personal Team works)
#   BUNDLE_ID=com.example.crownsofcinder       # must be unique for your team
#   GODOT=~/Applications/Godot.app/Contents/MacOS/Godot   # optional
#   DEVICE_ID=00008101-...                     # optional; default: the first connected iPhone
# export_presets.cfg is changed only for the export and restored afterwards.
# See docs/IOS.md.
set -euo pipefail

cd "$(dirname "$0")/../.."
REPO="$(pwd)"
SETTINGS="${CROWNS_IOS_SETTINGS:-$HOME/.crowns_of_cinder_ios}"
[ -f "$SETTINGS" ] && source "$SETTINGS"
: "${TEAM_ID:?Set TEAM_ID in $SETTINGS (Xcode > Settings > Accounts)}"
: "${BUNDLE_ID:?Set BUNDLE_ID in $SETTINGS}"
GODOT="${GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
[ -x "$GODOT" ] || { echo "Godot not found; set GODOT in $SETTINGS" >&2; exit 1; }

OUT="$REPO/export/ios"
APP_NAME="CrownsOfCinder"

step() { printf '\n==> %s\n' "$*"; }

step "Finding the iPhone"
if [ -z "${DEVICE_ID:-}" ]; then
	JSON="$(mktemp)"
	xcrun devicectl list devices --json-output "$JSON" >/dev/null
	DEVICE_ID="$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical":
        print(hw.get("udid", d.get("identifier", "")))
        break
PY
)"
	rm -f "$JSON"
fi
[ -n "$DEVICE_ID" ] || { echo "No iPhone found. Plug it in, unlock it and tap Trust." >&2; exit 1; }
echo "Device: $DEVICE_ID"

step "Exporting the Xcode project with Godot"
mkdir -p "$OUT"
cp export_presets.cfg "$OUT.presets.bak"
restore() { mv -f "$OUT.presets.bak" "$REPO/export_presets.cfg" 2>/dev/null || true; }
trap restore EXIT
sed -i '' \
	-e "s|^application/app_store_team_id=.*|application/app_store_team_id=\"$TEAM_ID\"|" \
	-e "s|^application/bundle_identifier=.*|application/bundle_identifier=\"$BUNDLE_ID\"|" \
	export_presets.cfg
rm -rf "$OUT/$APP_NAME.xcodeproj" "$OUT/$APP_NAME" "$OUT/$APP_NAME.pck"
"$GODOT" --headless --path "$REPO" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$REPO" --export-debug "iOS" "$OUT/$APP_NAME.ipa" 2>&1 | grep -E "ERROR|WARNING: Project export" || true
restore
trap - EXIT
[ -d "$OUT/$APP_NAME.xcodeproj" ] || { echo "Godot did not write $OUT/$APP_NAME.xcodeproj" >&2; exit 1; }

step "Building and signing with Xcode"
xcodebuild -project "$OUT/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Debug \
	-destination "id=$DEVICE_ID" -derivedDataPath "$OUT/build" -allowProvisioningUpdates \
	-allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
	-quiet build
APP="$(find "$OUT/build/Build/Products" -maxdepth 2 -name "*.app" -path "*iphoneos*" | head -1)"
[ -n "$APP" ] || { echo "No .app was built" >&2; exit 1; }

step "Installing on the iPhone"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

step "Starting the game"
if ! LAUNCH_LOG="$(xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1)"; then
	echo "Installed, but it could not be started:"
	echo "$LAUNCH_LOG" | grep -m1 -o 'Unable to launch[^")]*' || echo "$LAUNCH_LOG" | tail -3
	echo "Unlock the phone and open Crowns of Caern."
	echo "(First time: Settings > General > VPN & Device Management > your Apple ID > Trust.)"
fi
echo
echo "Done: $(git log -1 --format='%h %s') is on the iPhone."
