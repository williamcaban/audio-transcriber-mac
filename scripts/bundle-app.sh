#!/bin/bash
# Builds AudioTranscriberMac in release configuration and assembles it into
# a real .app bundle. There's no .xcodeproj here (see Package.swift's
# comment history / README for why), so this hand-rolls the handful of
# things Xcode would normally do automatically: copy the executable and any
# SPM-generated resource bundles into the right Contents/ subpaths, and
# attach Info.plist.
#
# Usage: scripts/bundle-app.sh
# Produces: dist/Audio Transcriber.app
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Audio Transcriber"
EXECUTABLE_NAME="AudioTranscriberMac"
CONFIG="release"

# Explicit, not relying on whatever `swift build` defaults to.
# `swift build --help` shows "swiftbuild" as the default build system on
# this machine's Swift 6.4 toolchain; CI's Swift 6.3.3 may default
# differently. This is still a hypothesis being tested, not a confirmed
# fix -- the confirmed facts are: CI resolves the exact same mlx-swift
# commit as a working local build, downloading the Metal Toolchain
# component on CI didn't fix the missing default.metallib, and the only
# other variable left is the build engine actually used. If this doesn't
# fix it, the next thing to check is CI's own `swift build --help` output.
BUILD_SYSTEM_FLAG="--build-system swiftbuild"

swift build $BUILD_SYSTEM_FLAG -c "$CONFIG"
BIN_PATH=$(swift build $BUILD_SYSTEM_FLAG -c "$CONFIG" --show-bin-path)

rm -rf dist
APP_BUNDLE="dist/${APP_NAME}.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp scripts/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# SPM writes declared target resources (the bundled libri_sample.wav test
# fixture) into a sibling <Package>_<Target>.bundle next to the executable,
# not hardcoded here since the exact name is an SPM implementation detail --
# copy whatever actually got produced.
shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle; do
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done
shopt -u nullglob

# mlx-swift's own metallib loader (mlx/backend/metal/device.cpp) looks for
# the shader library in a short list of fixed locations, none of which is
# this bundle's own Contents/Resources -- without this the app launches and
# immediately exits with "MLX error: Failed to load the default metallib."
# (never caught before, since `swift run`'s flat build layout, where the
# executable and its *.bundle resources sit side by side, happens to satisfy
# one of those locations on its own). The simplest one to satisfy in a real
# .app is its first: a bare "mlx.metallib" right next to the executable --
# confirmed by reading mlx-swift's actual source after hitting this for
# real, not guessed. (A "Resources" subdirectory next to the executable also
# satisfies the loader, but codesign treats it as a nested component needing
# its own signature and rejects it as unsigned -- a bare file avoids that.)
METALLIB=$(find "$APP_BUNDLE/Contents/Resources" -name "default.metallib" | head -1)
if [ -n "$METALLIB" ]; then
    cp "$METALLIB" "$APP_BUNDLE/Contents/MacOS/mlx.metallib"
fi

echo "Built: $APP_BUNDLE"
