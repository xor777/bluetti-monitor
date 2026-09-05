#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
build_dir="$project_dir/.build"
app_dir="$project_dir/dist/Bluetti Monitor.app"
contents_dir="$app_dir/Contents"
export SDKROOT=$sdk
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/swiftpm-module-cache"

swift build \
  --package-path "$project_dir" \
  --disable-sandbox \
  --configuration release \
  --product BluettiMonitor \
  --sdk "$sdk" \
  --arch arm64 \
  --scratch-path "$build_dir" \
  --cache-path "$build_dir/swiftpm-cache" \
  -Xswiftc -module-cache-path \
  -Xswiftc "$build_dir/module-cache"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$build_dir/arm64-apple-macosx/release/BluettiMonitor" "$contents_dir/MacOS/BluettiMonitor"

resource_bundle="$build_dir/arm64-apple-macosx/release/BluettiMonitor_BluettiCore.bundle"
test -d "$resource_bundle"
ditto "$resource_bundle" "$contents_dir/Resources/${resource_bundle:t}"
for localized_info in "$resource_bundle"/*.lproj/InfoPlist.strings; do
  language_dir=${localized_info:h:t}
  mkdir -p "$contents_dir/Resources/$language_dir"
  cp "$localized_info" "$contents_dir/Resources/$language_dir/InfoPlist.strings"
done

codesign --force --sign - \
  --entitlements "$project_dir/Resources/BluettiMonitor.entitlements" \
  "$app_dir"

touch "$app_dir"

print -r -- "$app_dir"
