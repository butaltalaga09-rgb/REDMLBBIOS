"""Patch Python dependencies that assume desktop-only modules exist on iOS.

The embedded iOS Python runtime intentionally excludes tkinter and cannot spawn
subprocesses. Keep UnityPy's harmless messagebox constant available without
pulling in tkinter, and let archspec use generic CPU detection on iOS.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_archspec_ios.py <site-packages>")
root = Path(sys.argv[1])

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

# Guard against this specific desktop-only import reappearing before packaging.
remaining = game_object.read_text(encoding="utf-8")
if "from tkinter.messagebox import NO" in remaining or "import tkinter" in remaining:
    raise SystemExit("UnityPy still contains a tkinter import after iOS patching")
