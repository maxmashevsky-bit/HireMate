#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Синтаксический разбор, без заявления о typecheck/SDK compatibility.
while IFS= read -r file; do
    swiftc -frontend -parse "$file"
done < <(rg --files App Features Core Tests -g '*.swift')
plutil -lint Resources/Info.plist MaxInterviewCopilot.xcodeproj/project.pbxproj
if [[ -f scripts/check-project.py ]]; then
    python3 scripts/check-project.py
fi
