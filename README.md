# Calculator / CipherVault (iOS)

Private iPhone calculator with a **local, authenticated, encrypted file vault**.

> **Development prototype. NOT security audited, not production ready, not uploaded to TestFlight.**
> GitHub contains source code only, never plaintext vault contents or encryption keys.

## Setup

- Bundle identifier: `com.jdarkyeka6.calculator`
- Native SwiftUI / iOS 17+ / Swift 5.9 / Xcode 16+
- Install XcodeGen (`brew install xcodegen`), run `xcodegen generate`, open `Calculator.xcodeproj`
- Select your Apple development team in Signing & Capabilities.
- Requires a real Face ID iPhone or a Simulator configured for enrolled Face ID.

## Features implemented in this branch

- Functional four-operation calculator; a matching 6–12 digit code followed by `=` starts unlock.
- Biometric-only Face ID via LocalAuthentication, then a 3×3 drag-pattern PIN.
- 256-bit master key in iOS Keychain with `biometryCurrentSet` access control.
- AES-GCM per-chunk encryption for large files and AES-GCM encrypted metadata/index.
- Salted PBKDF2 verifiers and temporary lockout after five failed attempts.
- Files picker supporting on-device storage, iCloud Drive, and integrated providers such as Google Drive.
- Photos picker, including selected photos and videos, with current encoding requested.
- Duplicates skipped by SHA-256, byte-for-byte encrypted inputs, embedded metadata retained.
- Original source files untouched; vault locks after every import batch.
- Protected temporary previews, on-device notes, basic encrypted media playback and explicit export.
- Decoy vault via separate optional swipe pattern.
- Face-down fast lock and app-background lock.
- Local failed-attempt log (not a tamper-proof forensic record).

## Planned / limitations

- **Do not import irreplaceable data yet.** There is no recovery-key or backup system.
  If Face ID enrollment changes, the protected master key may become inaccessible.
- Original Photos metadata is preserved *where supplied by the provider*.
  File/date metadata on Photos picker temporary copies may be unavailable.
- Video previews decrypt to an iOS file-protected temporary local file and are wiped on lock.
- Files providers may require provider download before importing.
- Intruder video recording is **not implemented**. iOS requires permissions and visible recording disclosure.
- iOS cannot reliably launch arbitrary third-party apps when turned face down;
  the implemented action immediately locks and displays the calculator.
- Security log entries are stored in device-local settings, not in a forensic secure enclave log.
- CI checks unsigned iOS Simulator builds only. TestFlight requires signing setup.

## GitHub Actions secrets reserved for later TestFlight integration

`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`.

These four cover App Store Connect API authentication and team selection; provisioning
and distribution signing must also be configured before an actual TestFlight upload.

**Never commit:** .p8, .p12, provisioning profiles, recovery secrets, or personal media.
