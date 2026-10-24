#!/usr/bin/env python3
"""Keep Unity mesh/renderer object typetrees untouched during platform-string rewriting.

The converter's generic recursive string rewrite is intended for platform path
strings, not geometry or renderer dependency graphs. Re-serializing those object
types can disturb mesh/bone/material references in modified MLBB bundles.
"""
from pathlib import Path

converter = Path(__file__).resolve().parents[2] / "source" / "MLBB_iOS_Converter_Offline_Project" / "PythonApp" / "mlbb_ios_converter.py"
source = converter.read_text(encoding="utf-8")

needle = '''            else:
                try:
                    # IMPORTANT: tower destruction is controlled by a chain of
'''
replacement = '''            elif obj.type.name in {"Mesh", "MeshFilter", "MeshRenderer", "SkinnedMeshRenderer"}:
                # Preserve geometry and renderer dependency typetrees byte-for-byte.
                # These objects carry vertex streams, bone weights, bind poses and
                # material/mesh PPtrs; generic recursive platform-string rewriting
                # is unrelated to shader conversion and risks changing that graph.
                continue
            else:
                try:
                    # IMPORTANT: tower destruction is controlled by a chain of
'''
if source.count(needle) != 1:
    raise SystemExit(f"Expected exactly one generic object-rewrite block, found {source.count(needle)}")
if 'elif obj.type.name in {"Mesh", "MeshFilter", "MeshRenderer", "SkinnedMeshRenderer"}' not in source:
    source = source.replace(needle, replacement, 1)
    converter.write_text(source, encoding="utf-8")
source = converter.read_text(encoding="utf-8")
if 'elif obj.type.name in {"Mesh", "MeshFilter", "MeshRenderer", "SkinnedMeshRenderer"}' not in source:
    raise SystemExit("Mesh-preservation guard was not applied")
print("Applied mesh/renderer typetree preservation guard.")
