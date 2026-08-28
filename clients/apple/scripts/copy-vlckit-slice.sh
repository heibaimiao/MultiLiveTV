#!/bin/sh
# Copy the matching VLCKit xcframework slice into XCFrameworkIntermediates.
# CocoaPods 1.17 does not add a native target dependency on Pods-MultiLiveTV-*,
# so [CP] Copy XCFrameworks never runs unless the app target does this itself.
set -euo pipefail

if [ -z "${PODS_ROOT:-}" ] || [ -z "${PODS_XCFRAMEWORKS_BUILD_DIR:-}" ]; then
  echo "error: CocoaPods build settings missing. Open MultiLiveTV.xcworkspace after pod install." >&2
  exit 1
fi

case "${PLATFORM_NAME}" in
  appletvsimulator)
    name=TVVLCKit
    slice="${PODS_ROOT}/TVVLCKit/TVVLCKit.xcframework/tvos-arm64_x86_64-simulator"
    ;;
  appletvos)
    name=TVVLCKit
    slice="${PODS_ROOT}/TVVLCKit/TVVLCKit.xcframework/tvos-arm64"
    ;;
  iphonesimulator)
    name=MobileVLCKit
    slice="${PODS_ROOT}/MobileVLCKit/MobileVLCKit.xcframework/ios-arm64_i386_x86_64-simulator"
    ;;
  iphoneos)
    name=MobileVLCKit
    slice="${PODS_ROOT}/MobileVLCKit/MobileVLCKit.xcframework/ios-arm64_armv7_armv7s"
    ;;
  *)
    echo "note: skipping VLCKit slice copy for ${PLATFORM_NAME}"
    exit 0
    ;;
esac

if [ ! -d "${slice}" ]; then
  echo "error: missing ${slice}. Run pod install in clients/apple." >&2
  exit 1
fi

dest="${PODS_XCFRAMEWORKS_BUILD_DIR}/${name}"
mkdir -p "${dest}"
rsync -a --delete "${slice}/" "${dest}/"
echo "Copied ${slice} -> ${dest}"
