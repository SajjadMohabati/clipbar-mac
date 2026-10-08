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
    NAME="ClipBar $VERSION"
    DMG="dist/ClipBar-$VERSION.dmg"
    WORK=$(mktemp -d)
    trap 'hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT
    hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true

    # A writable image first, so Finder can store the window layout in it.
    hdiutil create -volname "$NAME" -size 60m -fs HFS+ -ov "$WORK/rw.dmg" >/dev/null
    hdiutil attach "$WORK/rw.dmg" -nobrowse -noautoopen >/dev/null
    VOLUME="/Volumes/$NAME"
    cp -R "$APP" "$VOLUME/"
    ln -s /Applications "$VOLUME/Applications"
    mkdir "$VOLUME/.background"
    cp Resources/dmg-background.tiff "$VOLUME/.background/background.tiff"

    # The window: background with the drag arrow, big icons, nothing else.
    hdiutil detach "$VOLUME" -quiet
    hdiutil attach "$WORK/rw.dmg" -noautoopen >/dev/null
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "ClipBar.app" of container window to {180, 186}
        set position of item "Applications" of container window to {480, 186}
        update without registering applications
        delay 1
        -- Finder sometimes ignores the first resize while the window is opening.
        set the bounds of container window to {200, 120, 860, 548}
        delay 1
        get the bounds of container window
        close
    end tell
end tell
APPLESCRIPT
    cp Resources/AppIcon.icns "$VOLUME/.VolumeIcon.icns"
    SetFile -a C "$VOLUME"
    rm -rf "$VOLUME/.fseventsd"
    sync
    hdiutil detach "$VOLUME" -quiet

    mkdir -p dist
    rm -f "$DMG"
    hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
    echo "packaged $DMG ($(du -h "$DMG" | cut -f1))"
fi
