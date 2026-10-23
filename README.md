# MLBB iOS Auto Converter — ishamlbbios

This is the separate iOS port of the MLBB iOS Auto Converter. The Android project remains in `ISHAMLBBIOS`.

## iOS project archive

Download **`MLBB_iOS_Converter_Offline_Project.zip`** from the ChatGPT conversation and extract its contents into the root of this repository. The archive contains the SwiftUI app, Objective-C/Python bridge, converter engine, ShaderVariants bundle assets, app icon, requirements, validation script, and the IPA build workflow.

This repository currently holds the workflow scaffold; the large Unity bundle assets and the full converter source are not committed here yet. The build action intentionally checks for those files before attempting a build.

## Build

After the archive contents are extracted and pushed to this repository, open **Actions → Build iOS IPA → Run workflow**. A successful run uploads an IPA artifact.

## Status and limitations

- No validated installable IPA has been produced from this repository yet.
- The workflow must build iOS ARM64 Python dependencies; macOS/Linux native wheels cannot be used in an iOS app.
- Static checks and a successful Xcode build do not prove that real hero materials and textures convert correctly. Test an actual copy of a Unity bundle before relying on the app.
- The initial testing IPA is not Apple App Store distribution signed; distribution requires the appropriate Apple signing and provisioning setup.
