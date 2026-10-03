# Chapter 21: The Release APK

> **Status:** plan. From a debug build to an APK testers install.

<!-- Section plan: each heading below gets written in full. -->

## Signing

*A release key and keeping it safe.*

## R8

*Shrinking dex from 52 MB to 5 MB, and keeping the classes the BEAM calls through JNI.*

## One APK per ABI

*Dropping the emulator's x86_64.*

## Trimming the OTP runtime

*Removing unused OTP apps from `otp.zip`, and the stale NIF that crashes the app.*

## Versions and release notes

*`versionCode`, `versionName`, and notes for every version.*

## Icons and splash

*Adaptive icons and the splash screen.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `docs/building.md`
- `android/app/build.gradle`
- `android/app/proguard-rules.pro`
- `docs/releases/`

## By the end

133 MB down to 51 MB, installed on a tester's phone.
