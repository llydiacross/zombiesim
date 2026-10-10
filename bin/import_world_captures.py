"""Validate preview DATA captures, downsample display tiles and stitch a north-up atlas."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageStat


VARIANTS = ("clear", "atmospheric")
REVISION_KEYS = (
    "schemaVersion", "captureVersion", "profile", "mapManifestSha256", "templatePlanSha256",
    "boundsRevision", "pitch", "cameraZ", "skylineManifestSha256", "size",
)


def expected_revision(world, skyline, skyline_sha256):
    bounds = world["cellBounds"]
    if (skyline.get("profile") != world["profileId"]
            or skyline.get("templatePlanSha256") != world["templatePlanSha256"]
            or skyline.get("cellSpan") != bounds["neighbourPitch"]
            or skyline.get("cellBounds", {}).get("revision") != bounds["revision"]):
        raise ValueError("skyline camera manifest differs from authoritative world revision")
    scale = skyline.get("scale")
    camera = skyline.get("cameraOrigin", [])
    if (not isinstance(scale, (int, float)) or not math.isfinite(scale) or not 0 < scale <= 128
            or len(camera) != 3 or not all(isinstance(c, (int, float)) and math.isfinite(c) for c in camera)
            or not 64 < camera[2] - 128 < 16384):
        raise ValueError("invalid skyline camera/scale")
    return {
        "schemaVersion": 1, "captureVersion": 4, "profile": world["profileId"],
        "mapManifestSha256": world["mapManifestSha256"],
        "templatePlanSha256": world["templatePlanSha256"],
        "boundsRevision": bounds["revision"], "pitch": bounds["neighbourPitch"],
        "cameraZ": skyline["cameraOrigin"][2] - 128,
        "skylineManifestSha256": skyline_sha256, "size": 1024,
    }


def revision_matches(actual, expected):
    return isinstance(actual, dict) and all(actual.get(k) == expected[k] for k in REVISION_KEYS)


def validate(run, world_data, data_root, skyline, skyline_sha256, image_size=256):
    """Read every input before publishing anything. Never trust a client filename/checksum alone."""
    world = world_data["world"]
    revision = expected_revision(world, skyline, skyline_sha256)
    if world["profileId"] != "preview" or run.get("schemaVersion") != 1:
        raise ValueError("only schema-1 preview capture runs are supported")
    if not revision_matches(run.get("revision"), revision):
        raise ValueError("capture run does not match both current authoritative hashes/bounds")
    if run.get("active") or run.get("restorationVerified") is not True:
        raise ValueError("original survivor restoration must be verified before import")
    cells = {str(c["id"]): c for c in world_data["cells"]}
    queued = {str(c["id"]): c for c in run["queue"]}
    if len(queued) != len(run["queue"]) or any(k not in cells for k in queued):
        raise ValueError("duplicate or unknown logical cell in queue")
    width, height = world["grid"]
    images = {v: {} for v in VARIANTS}
    source_meta = {v: {} for v in VARIANTS}
    root = Path(data_root).resolve()
    run_id = run["runId"]
    if not isinstance(run_id, str) or not run_id or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for c in run_id):
        raise ValueError("unsafe run identity")
    for variant in VARIANTS:
        for key, result in run.get("results", {}).get(variant, {}).items():
            if key not in queued or result.get("cellId") != int(key) or result.get("variant") != variant:
                raise ValueError("capture logical cell/variant identity mismatch")
            cell, job = cells[key], queued[key]
            x, y = int(key) % width, int(key) // width
            if job.get("map") != cell["map"] or job.get("x") != x or job.get("y") != y or y >= height:
                raise ValueError("capture map/grid identity mismatch")
            if result.get("ok") is not True or result.get("ready") is not True or not revision_matches(result.get("revision"), revision):
                raise ValueError("capture lacks a valid actual-client acknowledgement")
            if result.get("map") != cell["map"]:
                raise ValueError("actual-client map acknowledgement differs from authoritative recipe")
            expected_path = f"zombiesim/world_captures/{run_id}/{variant}/cell_{key}.png"
            if result.get("path") != expected_path or result.get("runId") != run_id:
                raise ValueError("capture output is not owned by this run")
            path = root.joinpath(*expected_path.split("/"))
            if not path.resolve().is_relative_to(root):
                raise ValueError("capture path escapes DATA root")
            raw = path.read_bytes()
            if len(raw) != result.get("bytes") or hashlib.sha256(raw).hexdigest() != result.get("sha256"):
                raise ValueError("capture checksum/length mismatch")
            with Image.open(path) as image:
                image.verify()
            with Image.open(path) as image:
                if image.format != "PNG" or image.size != (revision["size"], revision["size"]):
                    raise ValueError("capture PNG dimensions/format mismatch")
                image = image.convert("RGB")
                # A syntactically valid black/constant buffer is not a usable screenshot.
                if max(ImageStat.Stat(image).var) < 0.5:
                    raise ValueError("capture is a blank/constant render buffer")
                # Keep only display-sized pixels in memory; original source PNGs remain untouched in DATA.
                images[variant][key] = image.resize((image_size, image_size), Image.Resampling.LANCZOS)
            source_meta[variant][key] = {
                "sha256": result["sha256"], "bytes": len(raw), "map": cell["map"],
                "worldX": job["worldX"], "worldY": job["worldY"],
                "atmosphereState": result.get("atmosphereState"), "capturedAt": result.get("capturedAt"),
            }
    if not any(images.values()):
        raise ValueError("run contains no validated captures")
    return revision, images, source_meta


def import_run(run_path, world_path, data_root, output_root, tile_size=256, overview_size=3072, skyline_path=None):
    if tile_size not in (128, 256, 512) or not 128 <= overview_size <= 4096:
        raise ValueError("display tiles must be 128/256/512; overview must be <=4096")
    run = json.loads(Path(run_path).read_text(encoding="utf-8-sig"))
    world_data = json.loads(Path(world_path).read_text(encoding="utf-8-sig"))
    skyline_raw = Path(skyline_path or Path(world_path).with_name("zombiesim_skybox_preview.json")).read_bytes()
    skyline = json.loads(skyline_raw.decode("utf-8-sig"))
    revision, images, source_meta = validate(run, world_data, data_root, skyline,
                                           hashlib.sha256(skyline_raw).hexdigest(), tile_size)
    width, height = world_data["world"]["grid"]
    atlas_tile = max(1, min(overview_size // width, overview_size // height))
    atlas_width, atlas_height = width * atlas_tile, height * atlas_tile
    estimated_rgba = sum(len(v) for v in images.values()) * tile_size ** 2 * 4 + 2 * atlas_width * atlas_height * 4
    if estimated_rgba > 384 * 1024 ** 2:
        raise ValueError("display assets exceed 384 MiB uncompressed two-variant budget; reduce tile/overview size")
    root = Path(output_root)
    manifest = {
        "schemaVersion": 1, "captureVersion": revision["captureVersion"], "profile": "preview",
        "mapManifestSha256": revision["mapManifestSha256"],
        "templatePlanSha256": revision["templatePlanSha256"],
        "skylineManifestSha256": revision["skylineManifestSha256"],
        "boundsRevision": revision["boundsRevision"], "pitch": revision["pitch"],
        "cameraZ": revision["cameraZ"], "northUp": True, "sourceSize": revision["size"],
        "tileSize": tile_size, "grid": [width, height], "runId": run["runId"],
        "complete": all(len(images[v]) == len(world_data["cells"]) for v in VARIANTS),
        "estimatedRGBABytes": estimated_rgba, "variants": {},
    }
    owned = []
    encoded_bytes = 0
    for variant in VARIANTS:
        directory = root / "materials" / "worlds" / "preview" / "captured" / variant
        directory.mkdir(parents=True, exist_ok=True)
        atlas = Image.new("RGB", (atlas_width, atlas_height), (0, 0, 0))
        paths, metadata = {}, {}
        for key, image in images[variant].items():
            path = directory / f"cell_{key}.png"
            image.resize((tile_size, tile_size), Image.Resampling.LANCZOS).save(path)
            relative = f"worlds/preview/captured/{variant}/cell_{key}.png"
            paths[key] = relative
            raw = path.read_bytes()
            metadata[key] = {**source_meta[variant][key], "displaySha256": hashlib.sha256(raw).hexdigest()}
            atlas.paste(image.resize((atlas_tile, atlas_tile), Image.Resampling.LANCZOS),
                        ((int(key) % width) * atlas_tile, (int(key) // width) * atlas_tile))
            encoded_bytes += len(raw)
            owned.append("materials/" + relative)
        atlas_path = directory / "overview.png"
        atlas.save(atlas_path)
        encoded_bytes += atlas_path.stat().st_size
        owned.append(f"materials/worlds/preview/captured/{variant}/overview.png")
        manifest["variants"][variant] = {
            "complete": len(paths) == len(world_data["cells"]),
            "atlas": f"worlds/preview/captured/{variant}/overview.png",
            "atlasSize": [atlas_width, atlas_height], "cells": paths,
            "capturedCellCount": len(paths), "requiredCellCount": len(world_data["cells"]),
            "metadata": metadata,
        }
    manifest["encodedBytes"] = encoded_bytes
    manifest["ownedFiles"] = owned
    destination = root / "data_static" / "world_captures_preview.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Publish the manifest last. Partial output is deliberately not eligible for Satellite.
    destination.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, type=Path)
    parser.add_argument("--data-root", required=True, type=Path)
    parser.add_argument("--world", type=Path, default=Path("content") / "data_static" / "zombiesim_world_preview.json")
    parser.add_argument("--skyline", type=Path)
    parser.add_argument("--output", type=Path, default=Path("generated") / "world_captures_import")
    parser.add_argument("--stage-preview", action="store_true")
    parser.add_argument("--tile-size", type=int, default=256)
    parser.add_argument("--overview-size", type=int, default=3072)
    args = parser.parse_args()
    output = Path("content") if args.stage_preview else args.output
    manifest = import_run(args.run, args.world, args.data_root, output, args.tile_size, args.overview_size, args.skyline)
    print(json.dumps({k: manifest[k] for k in ("complete", "encodedBytes", "estimatedRGBABytes", "runId")}))


if __name__ == "__main__":
    main()
