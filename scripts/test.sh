#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
export SDKROOT=$sdk
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swiftpm-module-cache"

exec swift run \
  --package-path "$project_dir" \
  --disable-sandbox \
  --sdk "$sdk" \
  --arch arm64 \
  --scratch-path "$project_dir/.build" \
  --cache-path "$project_dir/.build/swiftpm-cache" \
  -Xswiftc -module-cache-path \
  -Xswiftc "$project_dir/.build/module-cache" \
  BluettiCoreTests
