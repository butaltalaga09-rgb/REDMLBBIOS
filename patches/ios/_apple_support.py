"""Minimal iOS stdout/stderr adapter for CPython's Apple log initialization.

Python-Apple-support's CPython build calls _apple_support.init_streams() during
Py_InitializeFromConfig. The project assembles its stdlib from host Python, so
provide the Apple-specific adapter explicitly in the bundled stdlib.
"""
import sys


class _AppleLogStream:
    encoding = "utf-8"
    errors = "replace"

    def __init__(self, log_write, log_type):
        self._log_write = log_write
        self._log_type = int(log_type)

    def write(self, text):
        if not isinstance(text, str):
            text = str(text)
        if text:
            self._log_write(self._log_type, text.encode("utf-8", "replace"))
        return len(text)

    def flush(self):
        return None

    def writable(self):
        return True

    def isatty(self):
        return False


def init_streams(apple_log_write, stdout_log_type, stderr_log_type):
    """Install streams backed by Apple's native unified logging callback."""
    sys.stdout = _AppleLogStream(apple_log_write, stdout_log_type)
    sys.stderr = _AppleLogStream(apple_log_write, stderr_log_type)
