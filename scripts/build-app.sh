#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SWIFT_DIR="$PROJECT_DIR/ContainerManagerApp"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Container Manager"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

echo "=== Container Manager — Build ==="
echo ""

# 1. Build Swift binary
echo "[1/4] Building Swift binary (release)..."
cd "$SWIFT_DIR"
swift build -c release 2>&1 | grep -E '(Build complete|error:|Linking)'
BINARY="$SWIFT_DIR/.build/release/ContainerManagerApp"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY"

# 2. Generate icon if missing
ICNS="$SWIFT_DIR/Resources/AppIcon.icns"
if [ ! -f "$ICNS" ]; then
    echo "[2/4] Generating app icon..."
    cd "$PROJECT_DIR"
    if [ -f ".venv/bin/python" ]; then
        .venv/bin/python scripts/generate_icon.py
    else
        python3 scripts/generate_icon.py
    fi
else
    echo "[2/4] App icon exists, skipping."
fi

# 3. Assemble .app bundle
echo "[3/4] Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/ContainerManagerApp"
cp "$SWIFT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 4. Done
echo "[4/4] Build complete!"
echo ""
echo "  App bundle: $APP_BUNDLE"
echo "  Binary:     $APP_BUNDLE/Contents/MacOS/ContainerManagerApp"
echo ""
echo "Run:  open \"$APP_BUNDLE\""
echo "  or: $APP_BUNDLE/Contents/MacOS/ContainerManagerApp"
