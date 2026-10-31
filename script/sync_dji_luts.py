#!/usr/bin/env python3
"""Archive the LUT downloads published in DJI's public download index."""

import argparse
import concurrent.futures
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import re
import sys
import time
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INDEX_URL = "https://www.dji.com/cn/downloads/softwares/osmo-nano-d-log-m-to-rec-709-vivid-lut"
RESOURCE_ROOT = ROOT / "LogBatch/Resources/DJI"
VENDOR_ROOT = ROOT / "vendor/dji"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def public_provenance(value):
    if isinstance(value, dict):
        result = {key: public_provenance(item) for key, item in value.items()}
        fields = [key for key, item in value.items() if isinstance(item, str) and result[key] != item]
        if fields:
            result["sanitizedURLFields"] = sorted(set(result.get("sanitizedURLFields", [])) | set(fields))
        return result
    if isinstance(value, list):
        return [public_provenance(item) for item in value]
    if isinstance(value, str) and value.startswith(("https://", "http://")):
        parts = urllib.parse.urlsplit(value)
        parameters = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
        private = {"auth_key", "token", "access_token", "api_key", "apikey", "signature", "sig",
                   "authorization", "password", "x-amz-signature", "x-amz-credential", "x-amz-security-token"}
        public = [(key, item) for key, item in parameters if key.lower() not in private]
        if len(public) != len(parameters):
            return urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(public)))
    return value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(public_provenance(value), ensure_ascii=False, indent=2) + "\n")


def fetch(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or not any(
        parts.hostname == host or parts.hostname.endswith("." + host)
        for host in ("dji.com", "djicdn.com", "djiits.com")
    ):
        raise ValueError("Unexpected download origin: " + url)
    encoded = urllib.parse.urlunsplit(parts._replace(
        path=urllib.parse.quote(parts.path, safe="/%+()"),
        query=urllib.parse.quote(parts.query, safe="=&%+"),
    ))
    request = urllib.request.Request(encoded, headers={"User-Agent": "LogBatch-Asset-Importer/1.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                result = response.read(64 * 1024 * 1024 + 1)
                if len(result) > 64 * 1024 * 1024:
                    raise ValueError("Download exceeds 64 MiB")
                return result, response.url
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def cube_info(data):
    """Validate a 3D CUBE without changing its bytes or clamping its values."""
    try:
        text = data.decode("utf-8-sig")
        encoding = "utf-8"
    except UnicodeDecodeError:
        text = data.decode("gb18030")
        encoding = "gb18030"
    size = None
    shaper_size = None
    domain_min = [0.0] * 3
    domain_max = [1.0] * 3
    count = 0
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        key = fields[0]
        if key == "TITLE":
            continue
        if key == "LUT_3D_SIZE":
            if size is not None or len(fields) != 2:
                raise ValueError(f"Invalid cube dimension at line {number}")
            size = int(fields[1])
            if not 2 <= size <= 128:
                raise ValueError("Cube dimension is outside 2...128")
        elif key == "LUT_1D_SIZE":
            if shaper_size is not None or len(fields) != 2:
                raise ValueError(f"Invalid shaper dimension at line {number}")
            shaper_size = int(fields[1])
            if not 2 <= shaper_size <= 65536:
                raise ValueError("Shaper dimension is outside 2...65536")
        elif key in ("LUT_1D_INPUT_RANGE", "LUT_3D_INPUT_RANGE"):
            values = [float(x) for x in fields[1:]]
            if len(values) != 2 or not all(math.isfinite(x) for x in values) or values[0] >= values[1]:
                raise ValueError(f"Invalid input range at line {number}")
            domain_min, domain_max = [values[0]] * 3, [values[1]] * 3
        elif key in ("DOMAIN_MIN", "DOMAIN_MAX"):
            values = [float(x) for x in fields[1:]]
            if len(values) != 3 or not all(math.isfinite(x) for x in values):
                raise ValueError(f"Invalid domain at line {number}")
            if key == "DOMAIN_MIN":
                domain_min = values
            else:
                domain_max = values
        else:
            values = [float(x) for x in fields]
            if len(values) != 3 or not all(math.isfinite(x) for x in values):
                raise ValueError(f"Invalid RGB sample at line {number}")
            count += 1
    expected = (size ** 3 if size else 0) + (shaper_size or 0)
    if expected == 0 or count != expected:
        raise ValueError(f"Expected {expected} samples, found {count}")
    if any(a >= b for a, b in zip(domain_min, domain_max)):
        raise ValueError("Empty or reversed domain")
    return {"dimension": size, "shaperDimension": shaper_size, "sampleCount": count,
            "domainMin": domain_min, "domainMax": domain_max, "textEncoding": encoding}


def discover(html):
    match = re.search(r'<script[^>]*id="_SSI_DATA_downloads"[^>]*>(.*?)</script>', html, re.S)
    if not match:
        raise ValueError("DJI download index is missing; do not replace the saved catalog")
    content = json.loads(match.group(1))
    packages = []
    for group in content["downloads"]["softwares"]["data"]:
        for software in group["softwares"]:
            platforms = [software.get(platform, {}) for platform in ("mac_os", "windows", "linux")]
            if "lut" not in software["name"].lower() and not any(
                ".cube" in link["url"].lower() for platform in platforms for link in platform.get("links", [])
            ):
                continue
            links = []
            seen = set()
            for platform in platforms:
                for link in platform.get("links", []):
                    if link["url"] not in seen:
                        links.append({**link, "version": platform.get("version", ""),
                                      "releaseDate": platform.get("release_at")})
                        seen.add(link["url"])
            packages.append({"id": software["slug"], "name": software["name"],
                             "sourcePage": "https://www.dji.com/downloads/softwares/" + software["slug"],
                             "products": software["products"], "downloads": links})
    if not packages:
        raise ValueError("The official index contains no LUT packages")
    return packages


def transform_kind(package):
    name = package["name"].lower()
    if "color grading" in name:
        return "creative", "rec709", "rec709"
    if "linear" in name:
        return "technical", "linear", "dlog"
    profile = "dlog2" if "d-log2" in name else "dlogM" if re.search(r"d-?log\s*m", name) else "dlog"
    output = "rec2020HLG" if "hlg" in name else "sRGB" if "srgb" in name else "rec709"
    # Phantom 4's package title does not identify its destination transfer function.
    if package["id"] == "transcoding-phantom-4":
        output = "unspecified"
    return "technical", profile, output


def import_package(package):
    result = {**package, "files": [], "luts": [], "errors": []}
    kind, profile, output = transform_kind(package)
    for index, link in enumerate(package["downloads"]):
        try:
            data, resolved_url = fetch(link["url"])
            filename = urllib.parse.unquote(PurePosixPath(urllib.parse.urlsplit(resolved_url).path).name)
            members = []
            if zipfile.is_zipfile(io.BytesIO(data)):
                archive_path = VENDOR_ROOT / "archives" / f'{package["id"]}-{index + 1}.zip'
                archive_path.parent.mkdir(parents=True, exist_ok=True)
                archive_path.write_bytes(data)
                with zipfile.ZipFile(io.BytesIO(data)) as archive:
                    for member in archive.infolist():
                        path = PurePosixPath(member.filename)
                        if member.is_dir() or "__MACOSX" in path.parts or path.name.startswith("._"):
                            continue
                        if path.suffix.lower() == ".cube":
                            if member.file_size > 64 * 1024 * 1024:
                                raise ValueError("Archive member exceeds 64 MiB")
                            members.append((member.filename, archive.read(member)))
                if not members:
                    raise ValueError("Archive contains no CUBE files")
                source_path = str(archive_path.relative_to(ROOT))
            else:
                cube_info(data)
                members.append((filename or package["id"] + ".cube", data))
                source_path = None
            for member_index, (member_name, cube) in enumerate(members, 1):
                info = cube_info(cube)
                identifier = package["id"] if len(members) == 1 else f'{package["id"]}-{member_index:02d}'
                if len(package["downloads"]) > 1:
                    identifier += f"-download-{index + 1}"
                path = RESOURCE_ROOT / "LUTs" / (identifier + ".cube")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(cube)
                member_output = output
                member_profile = profile
                if "gamma18" in member_name.lower():
                    member_profile = "gamma18"
                elif "gamma22" in member_name.lower():
                    member_profile = "gamma22"
                if "2srgb" in member_name.lower():
                    member_output = "sRGB"
                elif "2rec709" in member_name.lower():
                    member_output = "rec709"
                result["luts"].append({
                    "id": identifier, "packageID": package["id"],
                    "file": "LUTs/" + path.name, "originalName": member_name,
                    "sha256": digest(cube), "bytes": len(cube), **info,
                    "kind": kind, "inputProfile": member_profile, "outputProfile": member_output,
                    "style": "vivid" if "vivid" in package["name"].lower() else "standard",
                    "version": link.get("version", ""), "releaseDate": link.get("releaseDate"),
                })
                if source_path is None:
                    source_path = str(path.relative_to(ROOT))
            result["files"].append({"requestedURL": link["url"], "resolvedURL": resolved_url,
                                    "originalFilename": filename, "path": source_path,
                                    "sha256": digest(data), "bytes": len(data),
                                    "version": link.get("version", ""), "releaseDate": link.get("releaseDate")})
        except Exception as error:
            result["errors"].append({"url": link["url"], "error": str(error)})
    if not package["downloads"]:
        result["errors"].append({"error": "No download links in the official index"})
    return result


def verify():
    catalog = json.loads((RESOURCE_ROOT / "catalog.json").read_text())
    failures = []
    count = 0
    for package in catalog["packages"]:
        for original in package["files"]:
            data = (ROOT / original["path"]).read_bytes()
            assert digest(data) == original["sha256"], original["path"]
        for lut in package["luts"]:
            path = RESOURCE_ROOT / lut["file"]
            data = path.read_bytes()
            assert digest(data) == lut["sha256"] and len(data) == lut["bytes"], path
            info = cube_info(data)
            assert all(info[key] == lut[key] for key in info), path
            count += 1
        failures.extend((package["id"], error) for error in package["errors"])
    indexed = json.loads((VENDOR_ROOT / "source-index.json").read_text())
    assert {x["id"] for x in indexed["packages"]} == {x["id"] for x in catalog["packages"]}
    print(json.dumps({"packages": len(catalog["packages"]), "validatedCubes": count,
                      "failedDownloads": failures}, ensure_ascii=False, indent=2))
    return not failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="Fetch DJI's current index and LUT files")
    args = parser.parse_args()
    if not args.download:
        return 0 if verify() else 1
    if (RESOURCE_ROOT / "catalog.json").exists():
        parser.error("This importer is one-shot. The catalog is pinned; use a reviewed migration to update it.")
    html, resolved = fetch(INDEX_URL)
    packages = discover(html.decode())
    snapshot = {"checkedAt": "2026-10-30", "requestedURL": INDEX_URL, "resolvedURL": resolved,
                "htmlSHA256": digest(html), "packages": packages}
    write_json(VENDOR_ROOT / "source-index.json", snapshot)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(import_package, packages):
            results.append(result)
            print(f'{result["id"]}: {len(result["luts"])} cubes, {len(result["errors"])} errors', flush=True)
    catalog = {"schemaVersion": 1, "checkedAt": snapshot["checkedAt"],
               "indexURL": "https://www.dji.com/lut", "downloadIndexURL": resolved,
               "redistributionPermission": "unverified", "packages": results}
    if any(result["errors"] for result in results):
        write_json(VENDOR_ROOT / "import-failures.json", results)
        print("Import is incomplete. No runtime catalog was published.", file=sys.stderr)
        return 1
    write_json(RESOURCE_ROOT / "catalog.json", catalog)
    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main())
