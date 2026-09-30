#!/bin/zsh
set -euo pipefail

APP_NAME="AutoFilenameHelper"
DISPLAY_NAME="Auto Filename"
ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DEST_ROOT="$HOME/Applications"
DEST_APP="$DEST_ROOT/$APP_NAME.app"
ICON_SOURCE="/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns"

command -v xcrun >/dev/null 2>&1 || {
  echo "Error: Xcode Command Line Tools are required. Run: xcode-select --install" >&2
  exit 1
}

[[ -f "$ICON_SOURCE" ]] || {
  echo "Error: Finder icon not found at: $ICON_SOURCE" >&2
  exit 1
}

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DEST_ROOT"

/usr/bin/plutil -lint "$ROOT_DIR/Info.plist" >/dev/null
for strings_file in "$ROOT_DIR"/Resources/*.lproj/*.strings; do
  /usr/bin/plutil -lint "$strings_file" >/dev/null
done
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy standard macOS localization resources.
if [[ -d "$ROOT_DIR/Resources" ]]; then
  /bin/cp -R "$ROOT_DIR/Resources/"*.lproj "$APP_DIR/Contents/Resources/"
fi

ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

xcrun swiftc \
  -O \
  -whole-module-optimization \
  -target "$TARGET" \
  -framework AppKit \
  -framework QuickLookUI \
  "$ROOT_DIR/Sources/main.swift" \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Local ad-hoc signing avoids an unsigned bundle while keeping installation self-contained.
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null

rm -rf "$DEST_APP"
cp -R "$APP_DIR" "$DEST_APP"

# Refresh LaunchServices/Finder metadata where available.
/usr/bin/touch "$DEST_APP"

cat <<EOF
Installed successfully:
  $DEST_APP

Replace the old Shortcuts shell script with:
  exec \"$DEST_APP/Contents/MacOS/$APP_NAME\"

The Shortcut should continue passing its existing payload to stdin.
EOF
