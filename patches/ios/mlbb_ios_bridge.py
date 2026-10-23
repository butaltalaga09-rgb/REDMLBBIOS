"""App bridge for MLBB iOS Auto Converter with durable crash diagnostics."""
from __future__ import annotations
import faulthandler, json, os, sys, traceback
from pathlib import Path
_FAULT_STREAM = None

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
        log("Stage 1/6: validating input and shader selection")
        if not shaders.is_dir(): raise FileNotFoundError(f"iOS ShaderVariants folder not found: {shaders}")
        shader_bundles=[p for p in shaders.rglob("*.unity3d") if "shader" in p.name.lower()]
        if not shader_bundles: raise FileNotFoundError("No ShaderVariants .unity3d file was found in the selected shader folder.")
        mapping_file=shaders/"verified_shader_mappings.json"
        if not mapping_file.is_file(): log("NOTE: verified_shader_mappings.json is absent; converter defaults will be used.")
        log("Stage 2/6: enabling fatal-signal diagnostics")
        try:
            if _FAULT_STREAM is None or _FAULT_STREAM.closed: _FAULT_STREAM=log_path.open("a",encoding="utf-8",buffering=1)
            faulthandler.enable(file=_FAULT_STREAM,all_threads=True); log("faulthandler enabled")
        except (RuntimeError,OSError,ValueError) as exc: log(f"faulthandler unavailable: {type(exc).__name__}: {exc}")
        log("Stage 3/6: importing converter engine (UnityPy/native decoders)")
        import mlbb_ios_converter as engine
        log("Stage 4/6: converter engine import completed")
        engine.app_directory=lambda: shaders
        options=engine.ConvertOptions(create_zip=bool(create_zip),full_validation=bool(full_validation),strict_matching=True,preserve_shadows=bool(preserve_shadows))
        log("Stage 5/6: starting Unity bundle conversion")
        converter=engine.Converter(source,shaders,destination,options,logger=log,progress=lambda value,message:log(f"[{value:5.1f}%] {message}"))
        output_dir,output_zip,report=converter.convert()
        payload={"ok":True,"output_dir":str(output_dir),"output_zip":str(output_zip) if output_zip else None,"report":str(report),"log":str(log_path),"bundles":getattr(converter.stats,"bundles",None),"materials":getattr(converter.stats,"materials",None),"textures":getattr(converter.stats,"textures",None)}
        log("Stage 6/6: conversion returned successfully")
        return json.dumps(payload,ensure_ascii=False)
    except BaseException as exc:
        trace=traceback.format_exc(); log(f"FAILED: {type(exc).__name__}: {exc}"); log(trace)
        return json.dumps({"ok":False,"error":f"{type(exc).__name__}: {exc}","traceback":trace,"log":str(log_path)},ensure_ascii=False)
