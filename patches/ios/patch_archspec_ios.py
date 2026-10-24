"""Make archspec CPU detection safe on iOS, where subprocess/_posixsubprocess is unavailable.

etcpak imports archspec.cpu.host() during startup. On iOS, querying macOS sysctl
through subprocess is not supported, and CPython may not ship _posixsubprocess.
For iOS we deliberately return no sysctl output so archspec falls back to a
generic ARM microarchitecture instead of failing during import.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: patch_archspec_ios.py <site-packages>")
root = Path(sys.argv[1])
target = root / "archspec" / "cpu" / "detect.py"
if not target.is_file():
    raise SystemExit(f"Expected archspec CPU detector not found: {target}")

source = target.read_text(encoding="utf-8")
if "import subprocess" not in source:
    # An upstream archspec version may already have removed this dependency.
    print("archspec detect.py has no subprocess import; no patch needed")
    raise SystemExit(0)

source = source.replace(
    "import subprocess",
    "# subprocess is unavailable in this iOS CPython build; sysctl detection is disabled",
    1,
)
pattern = re.compile(
    r"(?ms)^def _check_output\([^\n]*\):\n.*?(?=^@functools\.lru_cache)",
)
replacement = (
    "def _check_output(args, env):\n"
    '    """iOS cannot spawn sysctl; let archspec use generic CPU detection."""\n'
    '    return ""\n\n'
)
source, count = pattern.subn(replacement, source, count=1)
if count != 1:
    raise SystemExit("Could not safely patch archspec _check_output; source layout changed")
target.write_text(source, encoding="utf-8")
print(f"Patched iOS-safe generic CPU detection: {target}")
