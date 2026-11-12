#!/bin/sh
# Prebuilds clerk-ios for Exact: `bun exact.mjs clerk`.
#
# Exact compiles modules/apple/*.swift with swiftc and links modules/apple/*.xcframework, but has no Swift
# packages yet. So this builds clerk-ios (ClerkKit, ClerkKitUI and their dependencies) once into one static
# library per platform, modules/apple/Clerk.xcframework, and copies its resource bundles into
# assets/clerk/<ios|macos>, which Exact ships in the app as they are. modules/apple/Clerk.swift tells
# clerk-ios to look for them there.
set -eu

VERSION=1.7.1
cd "$(dirname "$0")/.."
work="$PWD/.exact/clerk-ios"
rm -rf "$work" modules/apple/Clerk.xcframework assets/clerk
git clone --quiet --depth 1 --branch "$VERSION" https://github.com/clerk/clerk-ios.git "$work/source"

slices=""
for platform in iphonesimulator iphoneos macosx; do
  case $platform in
    iphonesimulator) destination="generic/platform=iOS Simulator" products="Debug-iphonesimulator" ;;
    iphoneos) destination="generic/platform=iOS" products="Debug-iphoneos" ;;
    macosx) destination="generic/platform=macOS" products="Debug" ;;
  esac
  # Debug, because Clerk.swift points clerk-ios at assets/clerk with PACKAGE_RESOURCE_BUNDLE_PATH, which SwiftPM
  # reads only in Debug builds. A Release build looks for the bundles at the app bundle's top level, and stops there.
  (cd "$work/source" && xcodebuild build -quiet -scheme ClerkKitUI -configuration Debug \
    -destination "$destination" -derivedDataPath "$work/build" CODE_SIGNING_ALLOWED=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES)

  products="$work/build/Build/Products/$products"
  mkdir -p "$work/$platform/include"
  libtool -static -o "$work/$platform/libClerk.a" "$products"/*.o
  cp -R "$products"/*.swiftmodule "$work/$platform/include/"
  # ABI baselines no build reads; Exact would capture them as app sources (.json).
  find "$work/$platform/include" -name '*.abi.json' -delete
  slices="$slices -library $work/$platform/libClerk.a -headers $work/$platform/include"

  # Each platform has its own compiled asset catalogs.
  case $platform in
    iphoneos) resources=assets/clerk/ios ;;
    macosx) resources=assets/clerk/macos ;;
    *) continue ;;
  esac
  mkdir -p "$resources"
  cp -R "$products"/*.bundle "$resources/"
  find "$resources" -name _CodeSignature -prune -exec rm -rf {} +
done
xcodebuild -create-xcframework $slices -output modules/apple/Clerk.xcframework
echo "clerk-ios $VERSION: modules/apple/Clerk.xcframework, assets/clerk"
