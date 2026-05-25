#!/usr/bin/env bash
# Patch tflite_flutter's iOS podspec to use a newer TensorFlowLite
# version than the package's hardcoded 2.12.0 pin.
#
# Why this exists:
#   tflite_flutter 0.12.1 (latest on pub.dev) pins TensorFlowLite
#   to exactly 2.12.0 (April 2023). Our anti-spoof models were
#   converted via Google's `ai_edge_torch` (PyTorch → LiteRT, 2024+)
#   which targets TFLite ≥ 2.14 file schema and embeds int64
#   padding tensors + bool intermediates that the 2.12 interpreter
#   can't allocate ("Failed to allocate memory for input tensors"
#   from `Interpreter.allocateTensors()` on iOS).
#
#   This script patches the version in the cached podspec so the
#   newer runtime gets installed. Run AFTER `flutter pub get` (which
#   may overwrite or re-fetch the cache) and BEFORE `pod install`.
#
# Idempotent: safe to run multiple times.

set -euo pipefail

PUBSPEC_LOCK_PATH="${1:-$(dirname "$(dirname "$(realpath "$0")")")/pubspec.lock}"
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"

# Auto-detect the resolved tflite_flutter version from pubspec.lock
# so we don't have to update this script when the package version
# bumps. Bails out if the package isn't pinned.
TFLITE_FLUTTER_VERSION=$(awk '
  /^  tflite_flutter:/ { found = 1; next }
  found && /^    version:/ {
    gsub(/"/, "", $2); print $2; exit
  }
' "$PUBSPEC_LOCK_PATH")

if [[ -z "$TFLITE_FLUTTER_VERSION" ]]; then
  echo "tflite_flutter not found in $PUBSPEC_LOCK_PATH — nothing to patch."
  exit 0
fi

PODSPEC="$PUB_CACHE/hosted/pub.dev/tflite_flutter-$TFLITE_FLUTTER_VERSION/ios/tflite_flutter.podspec"
TARGET_TFLITE_VERSION="2.17.0"

if [[ ! -f "$PODSPEC" ]]; then
  echo "Podspec not found at $PODSPEC — skip"
  exit 0
fi

if grep -q "tflite_version = '$TARGET_TFLITE_VERSION'" "$PODSPEC"; then
  echo "Podspec already patched (tflite $TARGET_TFLITE_VERSION). Skipping."
  exit 0
fi

# Replace the version pin. The upstream uses `tflite_version = '2.12.0'`
# (single-quoted string). Cover both ' and " just in case.
sed -i.bak -E "s/tflite_version[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]/tflite_version = '$TARGET_TFLITE_VERSION'/" "$PODSPEC"

echo "Patched $PODSPEC → tflite $TARGET_TFLITE_VERSION"
