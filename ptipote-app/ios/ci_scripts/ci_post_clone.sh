#!/bin/sh
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH/ptipote-app"

git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter precache --ios
flutter pub get

PLUGIN_SWIFT_PACKAGE="ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ -f "$PLUGIN_SWIFT_PACKAGE" ]; then
  perl -0pi -e 's|\.iOS\("13\.0"\)|.iOS("15.0")|g' "$PLUGIN_SWIFT_PACKAGE"
fi

cd ios
pod install --repo-update
