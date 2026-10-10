"""Import user-cleared assets without installing addon Lua or replacement scripts."""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import tempfile
import zlib
import zipfile


ARCHIVES = {
    "hammer": ("chapstic_hammer.zip", "chapstic_hammer"),
    "machete": ("_3418-.rar", "Boba Fett's FC2 Machete/Required"),
    "spanner": ("spanner.7z", "Spanner"),
    "lewis": ("m249_lewis.rar", ""),
    "hev": ("hev_gordon_fixed_.rar", "H.E.V Gordon (fixed)"),
}
EXTENSIONS = {".mdl", ".vvd", ".vtx", ".phy", ".vmt", ".vtf", ".wav"}
GMA_MD5 = "4c142c65b506481382e8cd41e5a8620d"


def read_exact(stream, size):
    body = stream.read(size)
    if len(body) != size:
        raise ValueError("Truncated GMA")
    return body


def read_text(stream):
    body = bytearray()
    while True:
        char = read_exact(stream, 1)
        if char == b"\0":
            return body.decode("utf-8")
        body.extend(char)
        if len(body) > 65536:
            raise ValueError("Oversized GMA string")


def read_gma(data):
    if hashlib.md5(data).hexdigest() != GMA_MD5:
        raise ValueError("Archive is not the approved CS 1.6 revision")
    stream = io.BytesIO(data)
    if read_exact(stream, 5) != b"GMAD\x03":
        raise ValueError("Expected GMA version 3")
    read_exact(stream, 16)
    while read_text(stream):
        pass
    title, description, author = (read_text(stream) for _ in range(3))
    read_exact(stream, 4)
    entries, names = [], set()
    while struct.unpack("<I", read_exact(stream, 4))[0]:
        name = read_text(stream)
        if str(safe_path(name)) != name or name.lower() in names:
            raise ValueError(f"Unsafe or duplicate GMA path: {name}")
        names.add(name.lower())
        size, crc = struct.unpack("<qI", read_exact(stream, 12))
        if size < 0 or size > len(data):
            raise ValueError(f"Invalid GMA size: {name}")
        entries.append((name, size, crc))
    files = {}
    for name, size, crc in entries:
        body = read_exact(stream, size)
        if zlib.crc32(body) != crc:
            raise ValueError(f"GMA CRC mismatch: {name}")
        files[name] = body
    trailer = stream.read()
    if len(trailer) != 4 or zlib.crc32(data[:-4]) != struct.unpack("<I", trailer)[0]:
        raise ValueError("GMA footer CRC mismatch")
    return title, description, author, files


def cs16_assets(root, previous):
    archive = root / "assets" / "models" / "gmod_addons_2657591603_1637211535.zip"
    if not archive.exists():
        selected = {}
        for entry in previous["files"]:
            name = entry["path"]
            if not (name.startswith(("models/cs16/", "models/weapons/cs16/", "materials/weapons/cs16/",
                                     "sound/zombiesim/cs16/")) or name == "data_static/asset_credits/cs16_original.txt"):
                continue
            safe_path(name)
            body = (root / "content" / Path(name)).read_bytes()
            if len(body) != entry["bytes"] or hashlib.sha256(body).hexdigest() != entry["sha256"]:
                raise ValueError(f"Retained CS 1.6 asset differs from ownership: {name}")
            selected[name] = body
        if not selected:
            raise ValueError("CS 1.6 source archive and retained ownership are both unavailable")
        source = next((entry for entry in previous.get("sources", []) if entry["package"] == "cs16"), None)
        if source is None:
            source = {key: value for key, value in previous.items() if key not in ("files", "schemaVersion")}
            source["package"] = "cs16"
            source["archive"] = archive.name
        source["creditFiles"] = ["data_static/asset_credits/cs16_original.txt"]
        print("CS 1.6 archive absent: verified retained hash-owned assets.")
        return selected, source
    with zipfile.ZipFile(archive) as source:
        gmas = [item for item in source.infolist() if item.filename.endswith(".gma")]
        if len(gmas) != 1 or gmas[0].file_size > 64 * 1024 * 1024:
            raise ValueError("Expected one bounded CS 1.6 GMA")
        data = source.read(gmas[0])
        credits = source.read("2657591603_1637211535.desc.txt")
    title, _, _, files = read_gma(data)
    selected = {}
    for name, body in files.items():
        if name.startswith(("models/cs16/", "models/weapons/cs16/", "materials/weapons/cs16/")):
            selected[name] = body
        elif name.startswith("sound/") and name.endswith(".wav"):
            selected["sound/zombiesim/cs16/" + name[6:]] = body
    selected["data_static/asset_credits/cs16_original.txt"] = credits
    return selected, {
        "package": "cs16", "archive": archive.name, "title": title,
        "workshopId": "2657591603", "revision": "1637211535",
        "sourceGmaSha256": hashlib.sha256(data).hexdigest(),
        "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "credits": {"port": "Schwarz", "originalAssets": "Valve"},
        "creditFiles": ["data_static/asset_credits/cs16_original.txt"],
        "permission": "User-confirmed permission to bundle all included assets for non-commercial ZombieSim, 2026-10-10.",
    }


def safe_path(name):
    name = name.replace("\\", "/")
    path = PurePosixPath(name)
    if path.is_absolute() or ":" in name or ".." in path.parts:
        raise ValueError(f"Unsafe archive path: {name}")
    return path


def cstring(data, offset):
    if not 0 <= offset < len(data):
        raise ValueError("Invalid asset string offset")
    return data[offset:data.index(b"\0", offset)].decode("ascii")


def read_vpk(data):
    signature, version, tree_size = struct.unpack_from("<III", data)
    if signature != 0x55AA1234 or version not in (1, 2):
        raise ValueError("Unsupported owned VPK")
    header = 12 if version == 1 else 28
    at = header
    files = {}

    def text():
        nonlocal at
        value = cstring(data, at)
        at += len(value) + 1
        if at > header + tree_size:
            raise ValueError("VPK index exceeds tree")
        return value

    while True:
        extension = text()
        if not extension:
            break
        while True:
            directory = text()
            if not directory:
                break
            while True:
                name = text()
                if not name:
                    break
                crc, preload, index, offset, size, terminator = struct.unpack_from("<IHHIIH", data, at)
                at += 18
                if index != 0x7FFF or terminator != 0xFFFF:
                    raise ValueError("Expected bounded embedded VPK payload")
                body = data[at:at + preload]
                at += preload
                start = header + tree_size + offset
                body += data[start:start + size]
                if len(body) != preload + size or zlib.crc32(body) != crc:
                    raise ValueError("VPK payload CRC mismatch")
                path = str(safe_path(("" if directory == " " else directory + "/") + name + "." + extension)).lower()
                if path in files:
                    raise ValueError(f"Duplicate VPK path: {path}")
                files[path] = body
    return files


def relocate_model(data, package, material_paths):
    if data[:4] != b"IDST" or struct.unpack_from("<i", data, 4)[0] not in (44, 48):
        raise ValueError("Expected compatible Source model version 44/48")
    result = bytearray(data)
    count, offset = struct.unpack_from("<ii", data, 212)
    directories = []
    for index in range(count):
        pointer = offset + index * 4
        directory = cstring(data, struct.unpack_from("<i", data, pointer)[0]).replace("\\", "/").lower()
        if any(path.startswith(directory) for path in material_paths):
            directories.append(f"zombiesim/imported/{package}/{directory}")
        directories.append(directory)
    pointers = []
    for directory in directories:
        pointers.append(len(result))
        result.extend(directory.encode("ascii") + b"\0")
    struct.pack_into("<ii", result, 212, len(pointers), len(result))
    result.extend(struct.pack("<" + "i" * len(pointers), *pointers))
    struct.pack_into("<i", result, 76, len(result))
    return bytes(result)


def relocate_material(data, package, textures):
    text = data.decode("utf-8-sig")

    def replace(match):
        value = match[2].replace("\\", "/").lower().removesuffix(".vtf")
        if value + ".vtf" in textures:
            return match[1] + f"zombiesim/imported/{package}/{value}" + match[3]
        return match[0]

    return re.sub(r'((?:"\$[\w]+"|\$[\w]+)\s*")([^"]+)(")', replace, text).encode("utf-8")


def hammer_smd(files):
    mdl = files["models/weapons/v_knife_t.mdl"]
    vvd = files["models/weapons/v_knife_t.vvd"]
    vtx = files["models/weapons/v_knife_t.dx90.vtx"]
    integer = lambda data, at: struct.unpack_from("<i", data, at)[0]
    if integer(vtx, 0) != 7 or integer(vtx, 16) != integer(mdl, 8) or integer(vvd, 8) != integer(mdl, 8):
        raise ValueError("Hammer companion checksum mismatch")
    vertices = list(range(integer(vvd, 16)))
    if integer(vvd, 48):
        vertices = []
        for i in range(integer(vvd, 48)):
            _, source, count = struct.unpack_from("<iii", vvd, integer(vvd, 52) + i * 12)
            vertices.extend(range(source, source + count))
    materials = []
    for i in range(integer(mdl, 204)):
        at = integer(mdl, 208) + i * 64
        materials.append(cstring(mdl, at + integer(mdl, at)).lower())
    triangles = []
    for body in range(integer(mdl, 232)):
        part = integer(mdl, 236) + body * 16
        vpart = integer(vtx, 32) + body * 8
        for sub in range(integer(mdl, part + 4)):
            model = part + integer(mdl, part + 12) + sub * 148
            vmodel = vpart + integer(vtx, vpart + 4) + sub * 8
            lod = vmodel + integer(vtx, vmodel + 4)
            for mesh_index in range(integer(mdl, model + 72)):
                mesh = model + integer(mdl, model + 76) + mesh_index * 116
                material = materials[integer(mdl, mesh)]
                if "hammer" not in material:
                    continue
                first = integer(mdl, model + 84) // 48 + integer(mdl, mesh + 12)
                vmesh = lod + integer(vtx, lod + 4) + mesh_index * 9
                for group_index in range(integer(vtx, vmesh)):
                    group = vmesh + integer(vtx, vmesh + 4) + group_index * 25
                    for strip_index in range(integer(vtx, group + 16)):
                        strip = group + integer(vtx, group + 20) + strip_index * 27
                        count, first_index = struct.unpack_from("<ii", vtx, strip)
                        flags = vtx[strip + 18]
                        indices = []
                        for index in range(first_index, first_index + count):
                            vertex_index = struct.unpack_from("<H", vtx, group + integer(vtx, group + 12) + index * 2)[0]
                            original = struct.unpack_from("<H", vtx, group + integer(vtx, group + 4) + vertex_index * 9 + 4)[0]
                            at = integer(vvd, 56) + vertices[first + original] * 48
                            indices.append(struct.unpack_from("<8f", vvd, at + 16))
                        triples = [indices[i:i + 3] for i in range(0, count, 3)] if flags & 1 else [
                            [indices[i], indices[i + 1], indices[i + 2]] if i % 2 == 0 else
                            [indices[i + 1], indices[i], indices[i + 2]] for i in range(count - 2)]
                        triangles.extend(triple for triple in triples if len(triple) == 3 and len(set(triple)) == 3)
    if not triangles:
        raise ValueError("Hammer-only extraction produced no triangles")
    points = [vertex[:3] for triangle in triangles for vertex in triangle]
    center = [(min(p[a] for p in points) + max(p[a] for p in points)) / 2 for a in range(3)]
    lines = ['version 1', 'nodes', '0 "root" -1', 'end', 'skeleton', 'time 0', '0 0 0 0 0 0 0', 'end', 'triangles']
    for triangle in triangles:
        lines.append("hammertext")
        for x, y, z, nx, ny, nz, u, v in triangle:
            lines.append("0 " + " ".join(f"{value:.9g}" for value in (
                x - center[0], y - center[1], z - center[2], nx, ny, nz, u, v)) + " 1 0 1")
    lines.append("end")
    return "\n".join(lines) + "\n", len(triangles)


def import_assets(root):
    target = root / "content" / "data_static" / "imported_assets.json"
    previous = json.loads(target.read_text()) if target.exists() else {"files": [], "sources": []}
    selected, cs16 = cs16_assets(root, previous)
    sources = [cs16]
    hammer = None
    for package, (archive_name, base) in ARCHIVES.items():
        archive = root / "assets" / "models" / archive_name
        with tempfile.TemporaryDirectory(prefix="zombiesim-import-") as temporary:
            listing = subprocess.check_output(["tar", "-tf", str(archive)], text=True)
            for name in listing.splitlines():
                safe_path(name)
            verbose = subprocess.check_output(["tar", "-tvf", str(archive)], text=True)
            if any(line and line[0] not in "-d" for line in verbose.splitlines()):
                raise ValueError("Archive contains links or unsupported entry types")
            subprocess.run(["tar", "-xf", str(archive), "-C", temporary], check=True)
            folder = Path(temporary).joinpath(*PurePosixPath(base).parts)
            files = {}
            for path in folder.rglob("*"):
                if path.is_symlink():
                    raise ValueError("Archive contains a symbolic link")
                if not path.is_file():
                    continue
                relative = path.relative_to(folder).as_posix().lower()
                if path.suffix.lower() == ".vpk":
                    files.update(read_vpk(path.read_bytes()))
                else:
                    files[relative] = path.read_bytes()
            if package == "lewis":
                files["materials/models/weapons/v_models/hands/us_sleeve_vip.vmt"] = (
                    b'"Patch"\n{\n "include" "materials/models/weapons/v_models/hands/v_hands.vmt"\n}\n')
            material_paths = {name[10:] for name in files if name.startswith("materials/") and name.endswith(".vmt")}
            textures = {name[10:] for name in files if name.startswith("materials/") and name.endswith(".vtf")}
            for name, body in files.items():
                path = PurePosixPath(name)
                if path.suffix not in EXTENSIONS or path.parts[0] not in ("models", "materials", "sound"):
                    continue
                if path.parts[0] == "models":
                    destination = f"models/zombiesim/imported/{package}/" + name[7:]
                    if package == "lewis":
                        destination = destination.replace("v_mach_m249para", "v_lewis")
                    if path.suffix == ".mdl":
                        body = relocate_model(body, package, material_paths)
                elif path.parts[0] == "materials":
                    destination = f"materials/zombiesim/imported/{package}/" + name[10:]
                    if path.suffix == ".vmt":
                        body = relocate_material(body, package, textures)
                else:
                    destination = f"sound/zombiesim/imported/{package}/" + name[6:]
                selected[destination] = body
            credits_root = Path(temporary) / "Boba Fett's FC2 Machete" if package == "machete" else folder
            credits = list(credits_root.glob("*[Rr]ead*[Mm]e*.txt"))
            if credits and credits[0].stat().st_size:
                selected[f"data_static/asset_credits/gamebanana_{package}.txt"] = credits[0].read_bytes()
            sources.append({"package": package, "archive": archive_name,
                            "title": {"hammer": "Chapstic Hammer", "machete": "Boba Fett's FC2 Machete",
                                      "spanner": "Spanner", "lewis": "Lewis Gun", "hev": "HEV Gordon (fixed)"}[package],
                            "creditFiles": [name for name in selected if name == f"data_static/asset_credits/gamebanana_{package}.txt"],
                            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                            "permission": "User-confirmed creator permission for non-commercial ZombieSim, 2026-10-10; no supplied licence text."})
            if package == "hammer":
                hammer = hammer_smd(files)
    output = root / "generated" / "imported_assets"
    output.mkdir(parents=True, exist_ok=True)
    (output / "hammer.smd").write_text(hammer[0], encoding="ascii")
    qc = '\n'.join([
        '$modelname "zombiesim/imported/hammer/w_hammer.mdl"',
        '$cdmaterials "zombiesim/imported/hammer/models/weapons/v_models/hammer/"',
        '$body body "hammer.smd"', '$surfaceprop "metal"', '$sequence idle "hammer.smd"',
        '$collisionmodel "hammer.smd" { $concave }', '',
    ])
    (output / "hammer.qc").write_text(qc, encoding="ascii")
    game = output / "game"
    game.mkdir(exist_ok=True)
    (game / "gameinfo.txt").write_text('GameInfo { game "ZombieSim Asset Build" FileSystem { SteamAppId 4000 SearchPaths { Game "|gameinfo_path|." } } }', encoding="ascii")
    compiler = root.parents[2] / "bin" / "studiomdl.exe"
    result = subprocess.run([str(compiler), "-game", str(game), str(output / "hammer.qc")], capture_output=True)
    (output / "hammer-compile.log").write_bytes(result.stdout + result.stderr)
    model_folder = game / "models" / "zombiesim" / "imported" / "hammer"
    if result.returncode or not (model_folder / "w_hammer.mdl").exists():
        raise ValueError("Hammer model compilation failed; inspect generated/imported_assets/hammer-compile.log")
    for path in model_folder.iterdir():
        selected["models/zombiesim/imported/hammer/" + path.name] = path.read_bytes()
    previous_files = {entry["path"]: entry for entry in previous["files"]}
    for name, body in selected.items():
        destination = root / "content" / Path(name)
        if destination.exists() and destination.read_bytes() != body:
            entry = previous_files.get(name)
            if not entry or hashlib.sha256(destination.read_bytes()).hexdigest() != entry["sha256"]:
                raise ValueError(f"Refusing to overwrite different unowned/modified content: {name}")
    stale = []
    for name, entry in previous_files.items():
        if name in selected:
            continue
        safe_path(name)
        destination = root / "content" / Path(name)
        if destination.exists():
            if hashlib.sha256(destination.read_bytes()).hexdigest() != entry["sha256"]:
                raise ValueError(f"Previously imported asset was modified: {name}")
            stale.append(destination)
    for name, body in selected.items():
        destination = root / "content" / Path(name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists() or destination.read_bytes() != body:
            destination.write_bytes(body)
    for destination in stale:
        destination.unlink()
    manifest = {"schemaVersion": 1, "sources": sources, "hammerWorldTriangles": hammer[1],
                "files": [{"path": name, "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest()}
                          for name, body in sorted(selected.items())]}
    target.write_text(json.dumps(manifest, indent=2) + "\n", encoding="ascii")
    print(f"Imported {len(selected)} owned files; hammer-only world mesh: {hammer[1]} triangles.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    import_assets(parser.parse_args().root)
