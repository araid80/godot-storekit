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

# **먼저 비운다.** 덮어쓰기만 하면 예전 빌드의 `.a` 가 남아,
# 어느 것이 실제로 쓰이는지 헷갈린다 (Info.plist 만 보면 되지만 실제로 한 번 헤맸다).
rm -rf "$DST"
mkdir -p "$DST"
cp -R "$HERE/ios/"* "$DST"/
for kind in debug release; do
  [ -d "$DST/godotstorekit.$kind.xcframework" ] || {
    echo "[!!] godotstorekit.$kind.xcframework is missing — run ./build.sh first"; exit 1; }
done

# 쓰는 사람이 보는 줄이라 영어로 적는다. 코드 주석은 한국어 그대로다.
echo "[OK] iOS plugin installed into $DST"
echo "     Add to the iOS preset in export_presets.cfg:"
echo "       plugins/GodotStoreKit=true"
echo "       application/min_ios_version=\"15.0\"   (floor of StoreKit 2)"
echo "     Coming from godot-iap? Remove its iOS half only:"
echo "       addons/godot-iap/bin/ios/  ·  bin/godot_iap.gdextension"
