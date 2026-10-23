"""App bridge for MLBB iOS Auto Converter with durable crash diagnostics."""
from __future__ import annotations

import faulthandler
import json
import os
import sys
import traceback
from pathlib import Path

_FAULT_STREAM = None


def convert(
    input_path: str,
    shader_path: str,
    output_parent: str,
    create_zip: bool = True,
    full_validation: bool = True,
    preserve_shadows: bool = True,
) -> str:
    """Convert one imported Unity bundle or ZIP and return a JSON result."""
    global _FAULT_STREAM
    source = Path(input_path)
    shaders = Path(shader_path)
    destination = Path(output_parent)
    destination.mkdir(parents=True, exist_ok=True)
    log_path = destination / "ConversionLog.txt"

    def log(message: object) -> None:
        line = str(message).rstrip() + "\n"
        with log_path.open("a", encoding="utf-8") as stream:
            stream.write(line)
            stream.flush()
            try:
                os.fsync(stream.fileno())
            except OSError:
                pass

    # The native bridge writes a marker before importing this module. Keep it,
    # so the log still tells us how far execution got if import/conversion crashes.
    if not log_path.exists():
        log("Starting MLBB iOS Auto Converter")

    try:
        log(f"Python {sys.version.split()[0]}; executable={sys.executable}")
        log(f"Input: {source.name}; exists={source.is_file()}; bytes={source.stat().st_size if source.is_file() else 0}")
        log("Stage 1/6: validating input and bundled shaders")
        if not source.is_file():
            raise FileNotFoundError(f"Input file not found: {source}")
        if not shaders.is_dir():
            raise FileNotFoundError(f"Bundled iOS ShaderVariants folder not found: {shaders}")
        for required in (
            "ShaderVariants.unity3d",
            "ShaderVariantsInBattle.unity3d",
            "ShaderVariants_add.unity3d",
            "verified_shader_mappings.json",
        ):
            if not (shaders / required).is_file():
                raise FileNotFoundError(f"Missing bundled shader asset: {required}")

        log("Stage 2/6: enabling fatal-signal diagnostics")
        try:
            if _FAULT_STREAM is None or _FAULT_STREAM.closed:
                _FAULT_STREAM = log_path.open("a", encoding="utf-8", buffering=1)
            faulthandler.enable(file=_FAULT_STREAM, all_threads=True)
            log("faulthandler enabled")
        except (RuntimeError, OSError, ValueError) as exc:
            log(f"faulthandler unavailable: {type(exc).__name__}: {exc}")

        log("Stage 3/6: importing converter engine (UnityPy/native decoders)")
        import mlbb_ios_converter as engine
        log("Stage 4/6: converter engine import completed")

        engine.app_directory = lambda: shaders
        options = engine.ConvertOptions(
            create_zip=bool(create_zip),
            full_validation=bool(full_validation),
            strict_matching=True,
            preserve_shadows=bool(preserve_shadows),
        )
        log("Stage 5/6: starting Unity bundle conversion")
        converter = engine.Converter(
            source,
            shaders,
            destination,
            options,
            logger=log,
            progress=lambda value, message: log(f"[{value:5.1f}%] {message}"),
        )
        output_dir, output_zip, report = converter.convert()
        payload = {
            "ok": True,
            "output_dir": str(output_dir),
            "output_zip": str(output_zip) if output_zip else None,
            "report": str(report),
            "log": str(log_path),
            "bundles": getattr(converter.stats, "bundles", None),
            "materials": getattr(converter.stats, "materials", None),
            "textures": getattr(converter.stats, "textures", None),
        }
        log("Stage 6/6: conversion returned successfully")
        return json.dumps(payload, ensure_ascii=False)
    except BaseException as exc:
        # Do not swallow process-control exceptions silently, but preserve a
        # useful traceback for normal Python errors raised by the converter.
        trace = traceback.format_exc()
        log(f"FAILED: {type(exc).__name__}: {exc}")
        log(trace)
        return json.dumps(
            {"ok": False, "error": f"{type(exc).__name__}: {exc}", "traceback": trace, "log": str(log_path)},
            ensure_ascii=False,
        )
