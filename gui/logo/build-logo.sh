#!/bin/zsh
# build-logo.sh — regenerate the TeraScale Metal app icon from TeraScaleLogo.swift
#
# Outputs (next to this script):
#   logo-1024.png        full 1024x1024 icon
#   AppIcon.iconset/     16…512 @1x/@2x PNGs
#   AppIcon.icns         built with iconutil
#   preview.png          contact sheet (1024/256/64/32/16, light + dark)
#
# Needs only the Command Line Tools (swiftc, iconutil). ~1-2 min to compile, a few seconds to render.
set -euo pipefail
HERE="${0:A:h}"
TMP="$(mktemp -d -t terascale-logo)"
trap 'rm -rf "$TMP"' EXIT

echo "• compiling renderer"
swiftc -O "$HERE/TeraScaleLogo.swift" -o "$TMP/terascale-logo"

echo "• rendering"
rm -rf "$HERE/AppIcon.iconset"
"$TMP/terascale-logo" "$HERE"

echo "• building AppIcon.icns"
iconutil -c icns "$HERE/AppIcon.iconset" -o "$HERE/AppIcon.icns"

echo "done:"
ls -la "$HERE/logo-1024.png" "$HERE/AppIcon.icns" "$HERE/preview.png"
