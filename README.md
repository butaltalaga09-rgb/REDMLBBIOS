# MLBB iOS Auto Converter — ishamlbbios

This is the separate iOS port project for the MLBB iOS Auto Converter. The Android project remains in the original `ISHAMLBBIOS` repository.

## Project archive

Download **`MLBB_iOS_Converter_Offline_Project.zip`** from the ChatGPT conversation. It includes the SwiftUI app, Objective-C/Python bridge, conversion engine, bundled iOS ShaderVariants, shader mappings, app icon, iOS requirements, and validation/build scripts.

To use this repository's build workflow, upload that ZIP as a file named `MLBB_iOS_Converter_Offline_Project.zip` in the repository root. The workflow extracts it on the macOS runner, prepares the embedded iOS Python framework and native dependencies, and attempts to produce an IPA artifact.

## Build

After the ZIP has been added, open **Actions → Build iOS IPA → Run workflow**. A successful run uploads an artifact named `MLBB-iOS-Converter-IPA`. Adding the ZIP to the repo triggers the workflow automatically as well.

## Status / limitations

- The project source archive is ready; **no tested IPA has been produced yet**.
- iOS native Python dependencies have to be cross-built for iOS ARM64. macOS/Linux native wheels cannot run on iOS.
- A successful Xcode build does not by itself prove that real hero materials and textures convert properly. Real Unity bundle testing is still required.
- The workflow's initial IPA is for testing/sideloading workflows, not Apple App Store distribution signing.
