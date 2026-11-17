#!/bin/zsh
# Builds TSMetalEnabler.kext (Lilu plugin) with the Command Line Tools and the Lilu 1.7.1 SDK
# (vendor/lilu-1.7.1, the Resources of the official DEBUG release). Output: ../build/TSMetalEnabler.kext
set -euo pipefail
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path)
LILU=vendor/lilu-1.7.1/Lilu.kext/Contents/Resources
OUT=../build/TSMetalEnabler.kext
OBJ=../build/kext-obj
rm -rf $OUT $OBJ && mkdir -p $OUT/Contents/MacOS $OBJ

FLAGS=(-arch x86_64 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector -mmacosx-version-min=11.0 -Wno-sign-conversion -Wno-shadow
       -O2 -g -Wall -Wno-unused-parameter -Wno-deprecated-declarations
       -DKERNEL -DKERNEL_PRIVATE=0 -DPRODUCT_NAME=TSMetalEnabler -DMODULE_VERSION=1.0.0
       -I"$LILU" -I vendor/MacKernelSDK/Headers)
clang++ "${FLAGS[@]}" -std=gnu++17 -fapple-kext -fno-rtti -fno-exceptions -c TSMetalEnabler.cpp -o $OBJ/TSMetalEnabler.o
clang++ "${FLAGS[@]}" -std=gnu++17 -fapple-kext -fno-rtti -fno-exceptions -c "$LILU/Library/plugin_start.cpp" -o $OBJ/plugin_start.o
clang "${FLAGS[@]}" -c kmod_info.c -o $OBJ/kmod_info.o
clang++ -arch x86_64 -mkernel -nostdlib -Wl,-kext -L vendor/MacKernelSDK/Library/x86_64 -L"$SDK/usr/lib" -lkmodc++ -lkmod -lcc_kext \
    $OBJ/kmod_info.o $OBJ/TSMetalEnabler.o $OBJ/plugin_start.o -o $OUT/Contents/MacOS/TSMetalEnabler
cp Info.plist $OUT/Contents/Info.plist
codesign -s - -f $OUT
echo "built $OUT"
