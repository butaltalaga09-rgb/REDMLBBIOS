#!/usr/bin/env python3
"""Preserve the source Unity bundle's compression flags when saving converted assets.

UnityPy's forced packer="lz4" rewrites every bundle using a different block
layout, even when the source used another supported UnityFS layout. Keep the
original data/block-info flags so the output retains the bundle's original
container conventions while still serializing edited assets.
"""
from pathlib import Path

converter = (
    Path(__file__).resolve().parents[2]
    / "source"
    / "MLBB_iOS_Converter_Offline_Project"
    / "PythonApp"
    / "mlbb_ios_converter.py"
)
source = converter.read_text(encoding="utf-8")
old = 'return root.save(packer="lz4"), True'
new = 'return root.save(packer="original"), True'
if old in source:
    source = source.replace(old, new, 1)
    converter.write_text(source, encoding="utf-8")
elif new not in source:
    raise SystemExit("Could not find the expected Unity bundle save call.")
source = converter.read_text(encoding="utf-8")
if new not in source:
    raise SystemExit("Original Unity bundle compression flags are not preserved.")
print("Configured Unity bundle saves to preserve original compression flags.")
