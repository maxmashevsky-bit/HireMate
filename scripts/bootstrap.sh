#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uname -m
sw_vers
swift --version
xcrun --find swiftc
xcodebuild -version
sdk_path=$(xcrun --show-sdk-path)
if [[ ! -f "$sdk_path/System/Library/Frameworks/CoreFoundation.framework/Headers/CFBase.h" ]]; then
    echo 'SDK неполный: отсутствует CoreFoundation/CFBase.h. См. docs/release.md.' >&2
    exit 2
fi
