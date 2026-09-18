#!/bin/zsh
set -e
cd "$(dirname "$0")"
BUILD_DIR=$(mktemp -d /private/tmp/soundshelf-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
cp Sources/*.swift "$BUILD_DIR/"
mkdir -p "$BUILD_DIR/声屿.app/Contents/MacOS" "$BUILD_DIR/声屿.app/Contents/Resources"
swiftc -O -swift-version 5 -module-cache-path /private/tmp/soundshelf-module-cache -framework SwiftUI -framework AppKit -framework AVFoundation -framework CoreServices "$BUILD_DIR/"*.swift -o "$BUILD_DIR/SoundShelf"
cp "$BUILD_DIR/SoundShelf" "$BUILD_DIR/声屿.app/Contents/MacOS/SoundShelf"
pwd > "$BUILD_DIR/声屿.app/Contents/Resources/LibraryHome.txt"
cp Sources/taxonomy.json "$BUILD_DIR/声屿.app/Contents/Resources/taxonomy.json"
cp Sources/AppIcon.icns "$BUILD_DIR/声屿.app/Contents/Resources/AppIcon.icns"
cat > "$BUILD_DIR/声屿.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SoundShelf</string>
<key>CFBundleIdentifier</key><string>local.soundshelf.library</string>
<key>CFBundleName</key><string>声屿</string>
<key>CFBundleDisplayName</key><string>声屿</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>17</string>
<key>CFBundleShortVersionString</key><string>2.5</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$BUILD_DIR/声屿.app"
# Avoid AppleDouble files on external volumes when copying the signed bundle.
COPYFILE_DISABLE=1 cp -R -X "$BUILD_DIR/声屿.app" .
find "声屿.app" -name '._*' -type f -delete
codesign --verify --deep "声屿.app"
echo '声屿.app 构建完成'
