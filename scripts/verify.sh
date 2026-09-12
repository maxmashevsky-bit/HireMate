#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/build-paths.sh
./scripts/lint.sh
if [[ "${1:-}" == '--source-only' ]]; then
    ./scripts/test.sh --portable
    echo 'SOURCE-ONLY PASS: документы, синтаксис и portable core. Это НЕ полный verify приложения.'
    exit 0
fi
# Отдельный новый derivedDataPath обеспечивает clean build без удаления старых артефактов.
mkdir -p build/logs
verification_path="$hiremate_cache_root/Verify-$(date +%Y%m%d-%H%M%S)"
xcodebuild -project MaxInterviewCopilot.xcodeproj -scheme MaxInterviewCopilot -configuration Debug -destination 'platform=macOS' -derivedDataPath "$verification_path" SWIFT_VERSION=6.0 CODE_SIGN_IDENTITY=- build test 2>&1 | tee build/logs/verify.log
codesign --verify --deep --strict "$verification_path/Build/Products/Debug/MaxInterviewCopilot.app"
