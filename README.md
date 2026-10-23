# MLBB iOS Auto Converter — ishamlbbios

This is the separate iOS port project for the MLBB iOS Auto Converter. The Android project stays in the original `ISHAMLBBIOS` repository.

## Uploading the offline project ZIP

The 31 MB project ZIP is split into **four 8 MB-or-smaller chunks** to make GitHub uploads easier. Download all four files from the ChatGPT conversation:

- `MLBB_iOS_Converter_Offline_Project.zip.part00`
- `MLBB_iOS_Converter_Offline_Project.zip.part01`
- `MLBB_iOS_Converter_Offline_Project.zip.part02`
- `MLBB_iOS_Converter_Offline_Project.zip.part03`

Upload all four `.part` files into the **root of this repository in one commit**. Do not rename them or upload them inside a folder. The GitHub Actions workflow automatically concatenates them in filename order, validates the reconstructed ZIP, and extracts the project.

If you're building it manually, join them in order:

```bash
cat MLBB_iOS_Converter_Offline_Project.zip.part00 \
    MLBB_iOS_Converter_Offline_Project.zip.part01 \
    MLBB_iOS_Converter_Offline_Project.zip.part02 \
    MLBB_iOS_Converter_Offline_Project.zip.part03 \
    > MLBB_iOS_Converter_Offline_Project.zip
unzip -t MLBB_iOS_Converter_Offline_Project.zip
```

## Build

After all four parts have been uploaded, open **Actions → Build iOS IPA**. Uploading the parts to `main` will trigger the workflow automatically. A successful run uploads an artifact named `MLBB-iOS-Converter-IPA`.

## Status and limitations

- The project source archive is prepared; **an installable IPA has not yet been validated**.
- iOS native Python dependencies must be built for iOS ARM64. macOS/Linux native wheels cannot run on iOS.
- A successful Xcode build does not prove hero materials and textures convert correctly. Actual Unity bundle tests are still required.
- The workflow output is for testing/sideloading, not App Store distribution signing.
