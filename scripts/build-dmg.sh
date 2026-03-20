#!/bin/bash
set -euo pipefail

APP_NAME="ClaudePulse"
BUNDLE_ID="com.ccani.app"
VERSION="0.1.0"
SIGN_IDENTITY="Developer ID Application: ming hsien tzang (28C55B3F6N)"
NOTARY_PROFILE="ccani"
BUILD_DIR=".build/release"
APP_BUNDLE="build/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR="build/dmg"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf build
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${BUILD_DIR}/ccpulse" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClaudePulse needs access to send Apple Events to open Terminal.</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/tzangms/ccani/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>rdWqg6DxZAeugDCqV5pjjUUJck1xNni80UGLubN5wCI=</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Sign the app
echo "==> Signing app bundle..."
codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

codesign --force --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# Create DMG
echo "==> Creating DMG..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "build/${DMG_NAME}"

rm -rf "${DMG_DIR}"

# Sign the DMG
echo "==> Signing DMG..."
codesign --force --timestamp \
    --sign "${SIGN_IDENTITY}" \
    "build/${DMG_NAME}"

# Notarize
echo "==> Submitting for notarization..."
xcrun notarytool submit "build/${DMG_NAME}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

# Staple
echo "==> Stapling notarization ticket..."
xcrun stapler staple "build/${DMG_NAME}"

echo ""
echo "==> Done!"
echo "    App: ${APP_BUNDLE}"
echo "    DMG: build/${DMG_NAME} (signed + notarized)"
