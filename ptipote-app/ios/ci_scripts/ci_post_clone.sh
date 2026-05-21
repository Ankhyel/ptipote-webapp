#!/bin/sh
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH/ptipote-app"

export PATH="$HOME/development/flutter/bin:$PATH"

flutter --version
flutter pub get

cd ios
pod install --repo-update