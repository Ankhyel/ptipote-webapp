#!/bin/sh
set -e
set -x

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"
APP_DIR="$REPO_ROOT/ptipote-app"
FLUTTER_DIR="$HOME/flutter"

run_with_retry() {
  max_attempts="$1"
  shift
  attempt=1
  delay_seconds=10

  until "$@"; do
    exit_code="$?"
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "Command failed after $attempt attempt(s): $*"
      return "$exit_code"
    fi

    echo "Command failed with exit code $exit_code. Retrying in ${delay_seconds}s: $*"
    sleep "$delay_seconds"
    attempt=$((attempt + 1))
    delay_seconds=$((delay_seconds * 2))
    if [ "$delay_seconds" -gt 60 ]; then
      delay_seconds=60
    fi
  done
}

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

run_with_retry 5 flutter --version
run_with_retry 5 flutter precache --ios
run_with_retry 5 flutter pub get
run_with_retry 5 flutter build ios --config-only --no-codesign

PLUGIN_SWIFT_PACKAGE="ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ -f "$PLUGIN_SWIFT_PACKAGE" ]; then
  perl -0pi -e 's|\.iOS\("13\.0"\)|.iOS("15.0")|g' "$PLUGIN_SWIFT_PACKAGE"
else
  echo "Flutter generated plugin Swift package missing after iOS config generation: $PLUGIN_SWIFT_PACKAGE"
  find ios/Flutter -maxdepth 5 -print
  exit 7
fi

cd ios
pod --version
pod install --repo-update
