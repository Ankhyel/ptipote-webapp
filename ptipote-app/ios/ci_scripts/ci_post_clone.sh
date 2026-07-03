#!/bin/sh
set -e
set -x

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"
APP_DIR="$REPO_ROOT/ptipote-app"
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$APP_DIR" ]; then
  echo "Missing Flutter app directory: $APP_DIR"
  echo "CI_PRIMARY_REPOSITORY_PATH=$CI_PRIMARY_REPOSITORY_PATH"
  pwd
  ls -la "$REPO_ROOT"
  exit 1
fi

cd "$APP_DIR"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  rm -rf "$FLUTTER_DIR"
  git clone --depth 1 https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter precache --ios
flutter pub get

PLUGIN_SWIFT_PACKAGE="ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ -f "$PLUGIN_SWIFT_PACKAGE" ]; then
  perl -0pi -e 's|\.iOS\("13\.0"\)|.iOS("15.0")|g' "$PLUGIN_SWIFT_PACKAGE"
else
  echo "Flutter generated plugin Swift package not found yet: $PLUGIN_SWIFT_PACKAGE"
fi

cd ios
pod --version
pod install --repo-update
