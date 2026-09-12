#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/build-paths.sh
mkdir -p build/logs
if [[ "${1:-}" == '--clt' ]]; then
    echo 'Swift 5.9 больше не поддерживается. Для Swift 6 SPM используйте --spm; для app target — без аргументов.'
    exit 2
fi
if [[ "${1:-}" == '--spm' ]]; then
    echo 'Swift 6 SPM build; app target и TCC проверяются отдельно.'
    swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors 2>&1 | tee build/logs/clt-build.log
    executable_path=$(swift build --show-bin-path)
    bundle='build/MaxInterviewCopilot.app'
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cp "$executable_path/MaxInterviewCopilot" "$bundle/Contents/MacOS/MaxInterviewCopilot"
    cp -R Resources/Licenses "$bundle/Contents/Resources/"
    cp Resources/Info.plist "$bundle/Contents/Info.plist"
    codesign --force --sign - "$bundle"
    codesign --verify --deep --strict "$bundle"
else
    xcodebuild -project MaxInterviewCopilot.xcodeproj -scheme MaxInterviewCopilot -configuration Debug -destination 'platform=macOS' -derivedDataPath "$hiremate_derived_data" SWIFT_VERSION=6.0 CODE_SIGN_IDENTITY=- build 2>&1 | tee build/logs/xcode-build.log
    printf 'Приложение: %s/Build/Products/Debug/MaxInterviewCopilot.app\n' "$hiremate_derived_data"
fi
