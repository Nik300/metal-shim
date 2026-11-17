#!/bin/sh
# Builds "TeraScale Metal.app" (GUI + CLI in one executable) and the test emitter with swiftc/clang only.
# Output: metal-shim/build/TeraScale Metal.app, build/tsmtl-fake-emitter
set -eu
GUI=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$GUI")
OUT="$ROOT/build"
APP="$OUT/TeraScale Metal.app"
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
VERSION=1.3.2
BUILD=$(date +%Y%m%d%H%M)
CONFIG=${CONFIG:-release}

mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$CONFIG" = debug ]; then OPT="-Onone -g"; else OPT="-O"; fi
echo "swiftc ($CONFIG) -> $APP"
# TeraScale Swift's accelerator (plain C, shared with the driver) is linked into the app and bridged to Swift.
xcrun clang -O2 -Wall -target x86_64-apple-macosx26.0 -isysroot "$SDK" -c "$ROOT/src/swift/TSSwiftAccel.c" -o "$OUT/TSSwiftAccel.o"
# shellcheck disable=SC2086
xcrun swiftc $OPT -parse-as-library -swift-version 5 \
    -import-objc-header "$ROOT/src/swift/TSSwiftAccel.h" "$OUT/TSSwiftAccel.o" \
    -sdk "$SDK" -target x86_64-apple-macosx26.0 \
    -module-name TeraScaleMetal \
    -o "$APP/Contents/MacOS/TeraScaleMetal" \
    "$GUI"/Sources/*.swift \
    -framework SwiftUI -framework AppKit -framework Charts -framework IOKit

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>it</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>it</string>
	</array>
	<key>CFBundleAllowMixedLocalizations</key>
	<true/>
	<key>CFBundleExecutable</key>
	<string>TeraScaleMetal</string>
	<key>CFBundleIdentifier</key>
	<string>com.terascale.mtlshim.monitor</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>TeraScale Metal</string>
	<key>CFBundleDisplayName</key>
	<string>TeraScale Metal</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSHumanReadableCopyright</key>
	<string>TeraScale Metal Shim – progetto personale</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Optional artwork drawn separately in gui/logo/.
[ -f "$GUI/logo/AppIcon.icns" ] && cp "$GUI/logo/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" && echo "icona: AppIcon.icns"
[ -f "$GUI/logo/logo-1024.png" ] && cp "$GUI/logo/logo-1024.png" "$APP/Contents/Resources/logo-1024.png" && echo "logo: logo-1024.png"

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP" && echo "firmato (ad-hoc): $APP"

# CLI wrapper and test emitter.
chmod 755 "$GUI/tsmtl"
clang -O2 -Wall "$ROOT/tools/tsmtl-fake-emitter.c" -o "$OUT/tsmtl-fake-emitter"
echo "emitter: $OUT/tsmtl-fake-emitter"
