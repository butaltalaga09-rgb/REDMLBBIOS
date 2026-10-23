# MLBB iOS Auto Converter — iOS port

This repository is the separate iOS port of the existing MLBB iOS Auto Converter.

## Current status

**Work in progress — no installable IPA has been validated yet.**

The existing Python conversion engine and bundled iOS ShaderVariants are the source of truth. The iOS port needs an iOS-native file picker and output handling, a supported embedded Python runtime, and iOS-compatible builds of UnityPy's native dependencies.

A successful Xcode build alone is not considered sufficient. The build must also pass a converter smoke test and validate that the bundled ShaderVariants can be loaded and round-tripped before the IPA is advertised as usable.

## Planned output

- iOS ARM64 app, branded `ishamlbbios`
- Offline conversion workflow
- Import of `.unity3d` and ZIP files through the iOS Files picker
- Output saved under the app's Documents directory, with export/share support

The Android app and its build workflow are kept in the original `ISHAMLBBIOS` repository. This repository is for the separate iOS implementation.
