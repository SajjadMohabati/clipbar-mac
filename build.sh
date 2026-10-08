#!/bin/bash
# Usage: ./build.sh            build ClipBar.app
#        ./build.sh install    build, copy to /Applications and launch
#        ./build.sh dmg        build for Apple silicon and Intel, and package dist/ClipBar-<version>.dmg
#
# Signing: set CLIPBAR_SIGN_IDENTITY to a code-signing certificate name (e.g. a self-signed
# "ClipBar Local" made in Keychain Access) so the Accessibility permission survives rebuilds.
# Without it the app is ad-hoc signed and macOS asks for the permission again after each build.
set -euo pipefail
cd "$(dirname "$0")"

APP="./ClipBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${1:-}" == "dmg" ]]; then
    # The installer runs on any Mac, so it gets one binary for Apple silicon and Intel.
    BINARIES=()
    for ARCH in arm64 x86_64; do
        swift build -c release --triple "$ARCH-apple-macosx26.0"
        BINARIES+=("$(swift build -c release --triple "$ARCH-apple-macosx26.0" --show-bin-path)/ClipBar")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ClipBar"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/ClipBar" "$APP/Contents/MacOS/ClipBar"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign "${CLIPBAR_SIGN_IDENTITY:--}" --timestamp=none "$APP"
echo "built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x ClipBar 2>/dev/null || true
    rm -rf /Applications/ClipBar.app
    cp -R "$APP" /Applications/
    open /Applications/ClipBar.app
    echo "installed /Applications/ClipBar.app"
fi

if [[ "${1:-}" == "dmg" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    DMG="dist/ClipBar-$VERSION.dmg"
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    mkdir -p dist
    rm -f "$DMG"
    hdiutil create -volname "ClipBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    echo "packaged $DMG ($(du -h "$DMG" | cut -f1))"
fi
