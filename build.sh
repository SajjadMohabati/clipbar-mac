#!/bin/bash
# Usage: ./build.sh            build ClipBar.app
#        ./build.sh install    build, copy to /Applications and launch
#
# Signing: set CLIPBAR_SIGN_IDENTITY to a code-signing certificate name (e.g. a self-signed
# "ClipBar Local" made in Keychain Access) so the Accessibility permission survives rebuilds.
# Without it the app is ad-hoc signed and macOS asks for the permission again after each build.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="./ClipBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClipBar" "$APP/Contents/MacOS/ClipBar"
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
