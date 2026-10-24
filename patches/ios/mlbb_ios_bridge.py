"""App bridge for MLBB iOS Auto Converter with durable crash diagnostics."""
from __future__ import annotations
import faulthandler, json, os, sys, traceback
from pathlib import Path
_FAULT_STREAM = None


def _validate_converted_bundles(output_dir: Path, logger) -> dict:
    """Re-open every emitted Unity bundle; never report success for unreadable/empty output."""
    import UnityPy

    # ZIPs created on macOS may contain AppleDouble sidecar files under
    # __MACOSX/ with names such as ._hero_lancelot_skin.unity3d. They are
    # metadata, not Unity bundles, and UnityPy correctly finds no objects in them.
    # Never validate these as converted assets.
    candidates = sorted(
        p for p in output_dir.rglob("*.unity3d")
        if p.is_file()
        and not p.name.endswith(".bak")
        and not p.name.startswith("._")
        and "__MACOSX" not in p.parts
    )
    if not candidates:
        raise RuntimeError(f"Output validation failed: no .unity3d files found under {output_dir}")
    checked = 0
    total_objects = 0
    failures = []
    for path in candidates:
        try:
            env = UnityPy.load(str(path))
            objects = list(env.objects)
            if not objects:
                raise RuntimeError("UnityPy reopened the file but found zero serialized objects")
            # Access each object's type and path ID to force enumeration of the serialized
            # object table, rather than treating a successful header read as validation.
            for obj in objects:
                _ = obj.type.name
                _ = obj.path_id
            checked += 1
            total_objects += len(objects)
            logger(f"Output validation OK: {path.name}: {len(objects)} objects")
        except Exception as exc:
            failures.append(f"{path}: {type(exc).__name__}: {exc}")
            logger(f"Output validation FAILED: {path}: {type(exc).__name__}: {exc}")
    if failures:
        raise RuntimeError(
            "Output validation failed; conversion is NOT successful. "
            + " | ".join(failures[:8])
        )
    logger(f"Output validation passed: {checked} bundles, {total_objects} serialized objects.")
    return {"validated_bundles": checked, "validated_objects": total_objects}


def convert(input_path: str, shader_path: str, output_parent: str, create_zip: bool=True, full_validation: bool=True, preserve_shadows: bool=True) -> str:
    global _FAULT_STREAM
    source, shaders, destination = Path(input_path), Path(shader_path), Path(output_parent)
    destination.mkdir(parents=True, exist_ok=True)
    log_path = destination / "ConversionLog.txt"
    def log(message: object) -> None:
        with log_path.open("a", encoding="utf-8") as stream:
            stream.write(str(message).rstrip()+"\n"); stream.flush()
            try: os.fsync(stream.fileno())
            except OSError: pass
    if not log_path.exists(): log("Starting MLBB iOS Auto Converter")
    try:
        log(f"Python {sys.version.split()[0]}; executable={sys.executable}")
        if not source.exists() or not (source.is_file() or source.is_dir()):
            raise FileNotFoundError(f"Android input does not exist: {source}")
        if source.is_file() and source.suffix.lower()==".rar":
            raise ValueError("RAR extraction is not available in this iOS build. Extract the RAR in Files first or repack it as ZIP.")
        if source.is_file() and source.suffix.lower() not in {".unity3d",".zip",".rar"}:
            raise ValueError("Choose a .unity3d bundle, ZIP archive, or extracted input folder.")
        log("Stage 1/7: validating input and shader selection")
        if not shaders.is_dir(): raise FileNotFoundError(f"iOS ShaderVariants folder not found: {shaders}")
        shader_bundles=[p for p in shaders.rglob("*.unity3d") if "shader" in p.name.lower()]
        if not shader_bundles: raise FileNotFoundError("No ShaderVariants .unity3d file was found in the selected shader folder.")
        mapping_file=shaders/"verified_shader_mappings.json"
        if not mapping_file.is_file(): log("NOTE: verified_shader_mappings.json is absent; converter defaults will be used.")
        log("Stage 2/7: enabling fatal-signal diagnostics")
        try:
            if _FAULT_STREAM is None or _FAULT_STREAM.closed: _FAULT_STREAM=log_path.open("a",encoding="utf-8",buffering=1)
            faulthandler.enable(file=_FAULT_STREAM,all_threads=True); log("faulthandler enabled")
        except (RuntimeError,OSError,ValueError) as exc: log(f"faulthandler unavailable: {type(exc).__name__}: {exc}")
        log("Stage 3/7: importing converter engine (UnityPy/native decoders)")
        import mlbb_ios_converter as engine
        log("Stage 4/7: converter engine import completed")
        engine.app_directory=lambda: shaders
        options=engine.ConvertOptions(create_zip=bool(create_zip),full_validation=bool(full_validation),strict_matching=True,preserve_shadows=bool(preserve_shadows))
        log("Stage 5/7: starting Unity bundle conversion")
        converter=engine.Converter(source,shaders,destination,options,logger=log,progress=lambda value,message:log(f"[{value:5.1f}%] {message}"))
        output_dir,output_zip,report=converter.convert()
        log("Stage 6/7: reopening converted Unity bundles for validation")
        validation = _validate_converted_bundles(Path(output_dir), log)
        payload={"ok":True,"output_dir":str(output_dir),"output_zip":str(output_zip) if output_zip else None,"report":str(report),"log":str(log_path),"bundles":getattr(converter.stats,"bundles",None),"materials":getattr(converter.stats,"materials",None),"textures":getattr(converter.stats,"textures",None),"validation":validation}
        log("Stage 7/7: conversion and output validation returned successfully")
        return json.dumps(payload,ensure_ascii=False)
    except BaseException as exc:
        trace=traceback.format_exc(); log(f"FAILED: {type(exc).__name__}: {exc}"); log(trace)
        return json.dumps({"ok":False,"error":f"{type(exc).__name__}: {exc}","traceback":trace,"log":str(log_path)},ensure_ascii=False)
