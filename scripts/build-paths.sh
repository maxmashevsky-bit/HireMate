#!/bin/bash
# Артефакты вне Documents/File Provider: FinderInfo на вложенных bundles мешает codesign.
# Исходники и существующие build-каталоги не перемещаются и не очищаются.
hiremate_project_hash=$(printf '%s' "$PWD" | shasum -a 256 | cut -c 1-12)
hiremate_cache_root="$HOME/Library/Caches/dev.maxmashevsky.MaxInterviewCopilot/$hiremate_project_hash"
hiremate_derived_data="$hiremate_cache_root/DerivedData"
mkdir -p "$hiremate_cache_root"
