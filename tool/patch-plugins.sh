#!/usr/bin/env bash
# Applies temporary compatibility patches to plugins in the pub cache.
# flutter_inappwebview_android uses getDefaultProguardFile('proguard-android.txt'),
# which was removed in AGP 9. Runs after `flutter pub get`.
set -euo pipefail

CACHE="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev"

for gradle_file in "$CACHE"/flutter_inappwebview_android-*/android/build.gradle; do
  [ -f "$gradle_file" ] || continue
  sed -i "s/getDefaultProguardFile('proguard-android.txt')/getDefaultProguardFile('proguard-android-optimize.txt')/g" "$gradle_file"
  echo "Patched: $gradle_file"
done
