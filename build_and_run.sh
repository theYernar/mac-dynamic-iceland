#!/bin/zsh
set -e

APP_NAME="DynamicIsland"
APP_BUNDLE="${APP_NAME}.app"

echo "🔨 Building ${APP_NAME}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

swiftc \
    -module-cache-path /tmp/swift-module-cache \
    -O \
    -target arm64-apple-macosx14.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    Sources/DynamicIsland/**/*.swift \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/MediaRemoteHelper.swift" "${APP_BUNDLE}/Contents/Resources/MediaRemoteHelper.swift"

codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "✅ ${APP_BUNDLE} built successfully!"
if [[ "$1" != "--no-launch" ]]; then
    echo "🚀 Launching ${APP_BUNDLE}..."
    pkill -x "${APP_NAME}" 2>/dev/null || true
    open "${APP_BUNDLE}"
    echo "✨ Ready! Move the pointer over the camera notch at the top of the screen."
fi
