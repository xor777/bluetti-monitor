#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app="$project_dir/dist/Bluetti Monitor.app"
plist="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/BluettiMonitor"

test -d "$app"
test -x "$executable"
plutil -lint "$plist"

test "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" = "com.dmitry.bluetti-monitor"
test "$(plutil -extract LSUIElement raw -o - "$plist")" = "true"
test "$(plutil -extract LSMinimumSystemVersion raw -o - "$plist")" = "13.0"
bundle_version=$(plutil -extract CFBundleVersion raw -o - "$plist")
if (( bundle_version < 2 )); then
  print -u2 -r -- "CFBundleVersion must advance after the icon was added"
  exit 1
fi
if [[ "$plist" -nt "$app" ]]; then
  print -u2 -r -- "The app bundle is older than its contents; LaunchServices may reuse stale metadata"
  exit 1
fi
test "$(plutil -extract CFBundleIconFile raw -o - "$plist")" = "AppIcon.icns"
test -f "$app/Contents/Resources/AppIcon.icns"
file "$app/Contents/Resources/AppIcon.icns" | grep -q "Mac OS X icon"

icon_check_root=$(mktemp -d /private/tmp/bluetti-monitor-icon.XXXXXX)
trap 'rm -rf "$icon_check_root"' EXIT
iconutil -c iconset \
  -o "$icon_check_root/AppIcon.iconset" \
  "$app/Contents/Resources/AppIcon.icns"
test -f "$icon_check_root/AppIcon.iconset/icon_16x16@2x.png"
test -f "$icon_check_root/AppIcon.iconset/icon_32x32@2x.png"

file "$executable" | grep -q "arm64"

codesign --verify --deep --strict --verbose=2 "$app"
entitlements=$(codesign -d --entitlements :- "$app" 2>/dev/null)
print -r -- "$entitlements" | plutil -lint -
if print -r -- "$entitlements" | grep -q "com.apple.developer.usernotifications.time-sensitive"; then
  print -u2 -r -- "Restricted Time Sensitive entitlement is incompatible with local ad-hoc signing"
  exit 1
fi

print -r -- "Bluetti Monitor.app: verified"
