#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/build-paths.sh
mkdir -p build/logs
if [[ "${1:-}" == '--portable' ]]; then
    swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" -strict-concurrency=complete -warnings-as-errors Core/Domain/ContextProfile.swift Core/Domain/InputPolicy.swift Core/Infrastructure/FakeLLMProvider.swift Tests/Portable/CoreSmoke.swift -o build/core-smoke
    ./build/core-smoke | tee build/logs/portable-tests.log
else
    xcodebuild -project MaxInterviewCopilot.xcodeproj -scheme MaxInterviewCopilot -configuration Debug -destination 'platform=macOS' -derivedDataPath "$hiremate_derived_data" -resultBundlePath "$hiremate_cache_root/TestResults-$(date +%Y%m%d-%H%M%S).xcresult" SWIFT_VERSION=6.0 CODE_SIGN_IDENTITY=- test 2>&1 | tee build/logs/xcode-test.log
fi
