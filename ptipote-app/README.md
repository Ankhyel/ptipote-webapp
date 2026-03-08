# ptipote-app

Flutter app for PTIPOTE NFC workflows.

## Current scope
- Scan NFC and decode payloads.
- Reprogram chip fields (level/xp and later ownership flows).
- Connect to backend services (to be added).

## Project state
This folder is a Flutter skeleton prepared inside the monorepo.
Platform folders (`android/`, `ios/`, `web/`, etc.) are intentionally not generated here.

## First setup on your machine
1. Install Flutter SDK.
2. In this folder, run:
   ```bash
   flutter create .
   flutter pub get
   flutter run
   ```

## NFC setup (important)
After `flutter create .`, add platform permissions:

- Android: `android/app/src/main/AndroidManifest.xml`
  - add `<uses-permission android:name="android.permission.NFC" />`
  - add `<uses-feature android:name="android.hardware.nfc" android:required="false" />`

- iOS: `ios/Runner/Info.plist`
  - add `NFCReaderUsageDescription` with a user-facing message.

## Suggested next dependencies
- NFC: `nfc_manager`
- State management: `flutter_riverpod`
- Network: `dio`
- Local secure storage: `flutter_secure_storage`
