#!/bin/sh
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH/ptipote-app"

git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter precache --ios
flutter pub get

cd ios
pod install --repo-update
