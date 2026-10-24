"""Patch Python dependencies that assume desktop-only modules exist on iOS.

The embedded iOS Python runtime intentionally excludes tkinter and cannot spawn
subprocesses. Keep UnityPy's harmless messagebox constant available without
pulling in tkinter, and let archspec use generic CPU detection on iOS.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

if len(sys.argv) not in (2, 3):
    raise SystemExit("usage: patch_archspec_ios.py <site-packages> [PythonApp]")
root = Path(sys.argv[1])
app_root = Path(sys.argv[2]) if len(sys.argv) == 3 else None

# UnityPy imports tkinter.messagebox.NO only as a string constant. tkinter is a
# desktop GUI toolkit and is deliberately not part of the iOS Python runtime.
game_object = root / "UnityPy" / "classes" / "GameObject.py"
if not game_object.is_file():
    raise SystemExit(f"Expected UnityPy GameObject module not found: {game_object}")
game_source = game_object.read_text(encoding="utf-8")
tk_import = "from tkinter.messagebox import NO"
if tk_import in game_source:
    game_source = game_source.replace(
        tk_import,
        '# tkinter is unavailable on iOS; tkinter.messagebox.NO is the string "no".\nNO = "no"',
        1,
    )
    game_object.write_text(game_source, encoding="utf-8")
    print(f"Patched UnityPy desktop-only tkinter import: {game_object}")
elif "tkinter.messagebox" in game_source:
    raise SystemExit("Unexpected tkinter.messagebox import form in UnityPy GameObject.py")
else:
    print("UnityPy GameObject.py has no tkinter.messagebox import; no patch needed")

# archspec's CPU detector tries to execute macOS sysctl using subprocess. This
# iOS CPython build does not ship _posixsubprocess, so disable that probe.
target = root / "archspec" / "cpu" / "detect.py"
if not target.is_file():
    raise SystemExit(f"Expected archspec CPU detector not found: {target}")
source = target.read_text(encoding="utf-8")
if "import subprocess" in source:
    source = source.replace(
        "import subprocess",
        "# subprocess is unavailable in this iOS CPython build; sysctl detection is disabled",
        1,
    )
    pattern = re.compile(r"(?ms)^def _check_output\([^\n]*\):\n.*?(?=^@functools\.lru_cache)")
    replacement = (
        "def _check_output(args, env):\n"
        '    """iOS cannot spawn sysctl; use generic CPU detection."""\n'
        '    return ""\n\n'
    )
    source, count = pattern.subn(replacement, source, count=1)
    if count != 1:
        raise SystemExit("Could not safely patch archspec _check_output; source layout changed")
    target.write_text(source, encoding="utf-8")
    print(f"Patched iOS-safe generic CPU detection: {target}")
else:
    print("archspec detect.py has no subprocess import; no patch needed")

# UnityPy can recurse forever when a PPtr is only partially initialized:
# PPtr.__getattr__ asks get_obj(), which reads self._obj, which re-enters
# __getattr__ when _obj has not yet been assigned. Read the instance dict
# directly in get_obj and make missing _obj look like a normal missing attribute.
pptr = root / "UnityPy" / "classes" / "PPtr.py"
if not pptr.is_file():
    raise SystemExit(f"Expected UnityPy PPtr module not found: {pptr}")
pptr_source = pptr.read_text(encoding="utf-8")
old_guard = "if self._obj != None:"
new_guard = 'if self.__dict__.get("_obj") is not None:'
if old_guard in pptr_source:
    pptr_source = pptr_source.replace(old_guard, new_guard, 1)
    pptr.write_text(pptr_source, encoding="utf-8")
    print(f"Patched UnityPy PPtr partial-initialization recursion: {pptr}")
elif new_guard in pptr_source:
    print("UnityPy PPtr partial-initialization guard already present")
else:
    raise SystemExit("Could not safely patch PPtr.get_obj() guard; UnityPy source layout changed")

# Stop recursion when a PPtr is only partially initialized. In the reported
# crash, copy.copy() asks hasattr(pointer, "__setstate__"), __getattr__ calls
# get_obj(), and get_obj() reads file_id which re-enters __getattr__ forever.
# Guard all PPtr internals that must already exist before attempting resolution.
if "def __getattr__(self, attr):" in pptr_source:
    guard = '        if attr in ("file_id", "path_id", "assets_file", "_obj"):\n            try:\n                object.__getattribute__(self, attr)\n            except AttributeError:\n                raise AttributeError(attr) from None\n'
    if 'attr in ("file_id", "path_id", "assets_file", "_obj")' not in pptr_source:
        pptr_source = pptr_source.replace(
            "def __getattr__(self, attr):\n",
            "def __getattr__(self, attr):\n" + guard,
            1,
        )
        pptr.write_text(pptr_source, encoding="utf-8")
        print("Added safe initialization guard to UnityPy PPtr.__getattr__")
    else:
        print("UnityPy PPtr initialization guard already present")
else:
    print("UnityPy PPtr has no matching __getattr__; direct PPtr guard remains active")

# The converter copies a PPtr via copy.copy(). That invokes dynamic attribute
# lookup on the pointer itself; keep the reference instead of copying the proxy.
# Texture PPtr objects are references into the source asset file, not texture data.
if app_root is not None:
    converter = app_root / "mlbb_ios_converter.py"
    if not converter.is_file():
        raise SystemExit(f"Expected converter module not found: {converter}")
    converter_source = converter.read_text(encoding="utf-8")
    unsafe_copy = "reference_env.m_Texture = copy.copy(source_env.m_Texture)"
    safe_reference = "reference_env.m_Texture = source_env.m_Texture"
    if unsafe_copy in converter_source:
        converter_source = converter_source.replace(unsafe_copy, safe_reference, 1)
        converter.write_text(converter_source, encoding="utf-8")
        print(f"Patched unsafe copy of Unity texture PPtr: {converter}")
    elif safe_reference in converter_source:
        print("Unity texture PPtr assignment is already safe")
    else:
        raise SystemExit("Could not find the expected texture PPtr copy statement; converter source layout changed")

# Guard against this specific desktop-only import reappearing before packaging.
remaining = game_object.read_text(encoding="utf-8")
if "from tkinter.messagebox import NO" in remaining or "import tkinter" in remaining:
    raise SystemExit("UnityPy still contains a tkinter import after iOS patching")
