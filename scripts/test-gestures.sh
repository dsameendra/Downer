#!/bin/zsh
# Runs the gesture model tests. No Xcode project or signing needed.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/gesture-tests"
swiftc -swift-version 5 Downer/GestureModels.swift scripts/tests/gestures/main.swift -o "$OUT"
"$OUT"
