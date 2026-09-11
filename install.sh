#!/bin/bash
# iOS 플러그인 파일을 제자리로 옮긴다.
#
# **엔진이 `res://ios/plugins/` 한 곳만 본다** (editor_export_platform_apple_embedded.h
# 의 `get_plugins()`). 그래서 애드온 폴더 안에 둘 수가 없다.
#
#   cd addons/storekit && ./install.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DST="$ROOT/ios/plugins/godotstorekit"

mkdir -p "$DST"
cp -R "$HERE/ios/"* "$DST"/
for kind in debug release; do
  [ -d "$DST/godotstorekit.$kind.xcframework" ] || {
    echo "[!!] godotstorekit.$kind.xcframework 가 없다 — ./build.sh 를 먼저"; exit 1; }
done

echo "[OK] iOS 플러그인을 $DST 에 놓았다"
echo "     export_presets.cfg 의 iOS 프리셋에 적을 것:"
echo "       plugins/GodotStoreKit=true"
echo "       application/min_ios_version=\"15.0\"   (StoreKit 2 의 바닥)"
echo "     OpenIAP 을 쓰던 프로젝트라면 iOS 쪽을 들어낼 것:"
echo "       addons/godot-iap/bin/ios/  ·  bin/godot_iap.gdextension"
