#!/bin/bash
# iOS 플러그인을 다시 빌드한다.
#
#   ./build.sh [godot-ios-plugins 경로]
#
# **Swift 를 먼저 굽고 ObjC++ 와 합친다.** StoreKit 2 는 Swift 전용 API 라
# 브리지가 Swift 여야 하는데, Godot iOS 플러그인은 정적 라이브러리 하나만 받는다.
# 그래서 `libtool` 로 두 아카이브를 한 덩이로 만든다.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS="${1:-$HOME/Documents/works/godot-ios-plugins}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
# **엔진 태그와 같아야 한다.** 하네스의 godot/ 가 그 버전이어야 헤더가 맞는다.
TARGET="arm64-apple-ios15.0"     # StoreKit 2 의 바닥이 15.0 이다
WORK="$(mktemp -d)"

[ -d "$HARNESS/plugins" ] || { echo "[!!] 하네스가 없다: $HARNESS"; exit 1; }

echo "[1/4] Swift 브리지"
for kind in release debug; do
  EXTRA="" ; [ "$kind" = debug ] && EXTRA="-Onone -g"
  swiftc -emit-library -static -emit-objc-header \
    -emit-objc-header-path "$WORK/GodotStoreKit-Swift.h" \
    -module-name GodotStoreKit -target "$TARGET" -sdk "$SDK" $EXTRA \
    -o "$WORK/swift-$kind.a" "$HERE/native/ios/StoreKitBridge.swift"
done

echo "[2/4] ObjC++ 플러그인"
mkdir -p "$HARNESS/plugins/godotstorekit"
cp "$HERE/native/ios/"*.mm "$HERE/native/ios/"*.h "$HARNESS/plugins/godotstorekit/"
cp "$WORK/GodotStoreKit-Swift.h" "$HARNESS/plugins/godotstorekit/"
# 하네스의 SConstruct 에 플러그인 이름이 등록돼 있어야 한다
grep -q "'godotstorekit'" "$HARNESS/SConstruct" || {
  echo "[!!] $HARNESS/SConstruct 의 plugin 목록에 'godotstorekit' 를 넣을 것"; exit 1; }
( cd "$HARNESS" && for kind in release debug; do
    scons platform=ios target=$kind arch=arm64 version=4.0 plugin=godotstorekit -j8 >/dev/null
  done )

echo "[3/4] 합치기"
for kind in release debug; do
  libtool -static -o "$WORK/merged-$kind.a" \
    "$HARNESS/bin/libgodotstorekit.arm64-ios.$kind.a" "$WORK/swift-$kind.a" 2>/dev/null
done

echo "[4/4] xcframework"
# **디버그·릴리스 둘 다 있어야 한다** — 엔진이 둘 다 찾는다.
for kind in release debug; do
  rm -rf "$HERE/ios/godotstorekit.$kind.xcframework"
  xcodebuild -create-xcframework -library "$WORK/merged-$kind.a" \
    -output "$HERE/ios/godotstorekit.$kind.xcframework" >/dev/null
done
rm -rf "$WORK"
echo "[OK] ios/godotstorekit.{debug,release}.xcframework"
