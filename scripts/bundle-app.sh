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

swift build -c "$CONFIG"
BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)

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

echo "Built: $APP_BUNDLE"
