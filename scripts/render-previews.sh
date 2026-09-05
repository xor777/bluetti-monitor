#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
build_dir="$project_dir/.build"
output_dir=${1:-"$project_dir/.artifacts/ui-previews"}
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

mkdir -p "$output_dir"
"$build_dir/arm64-apple-macosx/release/BluettiMonitor" \
  --render-fixtures "$output_dir"

print -r -- "Preview gallery: $output_dir"
