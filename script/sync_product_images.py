#!/usr/bin/env python3
"""Fetch product artwork from DJI's product download pages and pin its provenance."""
import argparse
import concurrent.futures
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "LogBatch/Resources/ProductImages"


def fetch(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or not any(
        parts.hostname == host or parts.hostname.endswith("." + host)
        for host in ("dji.com", "djicdn.com", "djiits.com")
    ):
        raise ValueError("Unexpected origin: " + url)
    request = urllib.request.Request(url, headers={"User-Agent": "LogBatch-Asset-Importer/1.0"})
    with urllib.request.urlopen(request, timeout=40) as response:
        data = response.read(20 * 1024 * 1024 + 1)
        if len(data) > 20 * 1024 * 1024:
            raise ValueError("Image exceeds 20 MiB")
        return data, response.url


def image_info(path):
    output = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)], text=True)
    width = re.search(r"pixelWidth: (\d+)", output)
    height = re.search(r"pixelHeight: (\d+)", output)
    if not width or not height:
        raise ValueError("Image does not decode: " + str(path))
    return {"width": int(width[1]), "height": int(height[1]), "hasAlpha": "hasAlpha: yes" in output}


def load_product(product):
    identifier, title = product
    page = f"https://www.dji.com/{identifier}/downloads"
    data, resolved_page = fetch(page)
    source = data.decode()
    # DJI redirects the combined Pro/RAW download entry to the Pro support page.
    source_identifier = {"inspire-1-pro-and-raw": "inspire-1-pro"}.get(identifier, identifier)
    for _ in range(4):
        redirect = re.search(r'<meta[^>]+http-equiv="refresh"[^>]+content="[^";]*;\s*URL=([^"\s]+)', source, re.I)
        if not redirect:
            break
        data, resolved_page = fetch(urllib.parse.urljoin(resolved_page, html.unescape(redirect[1])))
        source = data.decode()
    def cover(value):
        if isinstance(value, dict):
            if value.get("slug", value.get("product_slug")) in (identifier, source_identifier) and isinstance(value.get("cover"), dict):
                image = value["cover"].get("url")
                if image:
                    return urllib.parse.urljoin("https://www-cdn.djiits.com/", image)
            for child in value.values():
                result = cover(child)
                if result:
                    return result
        elif isinstance(value, list):
            for child in value:
                result = cover(child)
                if result:
                    return result
        return None
    published_url = None
    next_data = re.search(r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>', source, re.S)
    if next_data:
        components = json.loads(next_data[1]).get("props", {}).get("initialState", {}).get("page", {}).get("data", {}).get("components_data", [])
        published_url = cover(components)
    match = re.search(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"', source)
    if not published_url and match and "de46652dd99c67d4f8d17607e3bf0dce" not in match[1]:
        published_url = html.unescape(match[1])
    if not published_url:
        raise ValueError("No product-specific artwork: " + page)
    image, resolved_image = fetch(published_url)
    suffix = ".png" if image.startswith(b"\x89PNG") else ".jpg" if image.startswith(b"\xff\xd8") else ".webp"
    path = DESTINATION / (identifier + suffix)
    path.write_bytes(image)
    info = image_info(path)
    origin_url = re.sub(r"@\d+\*\d+(?=\.)", "", published_url)
    selected_url = published_url
    if origin_url != published_url:
        try:
            original, original_resolved = fetch(origin_url)
            candidate = DESTINATION / (identifier + ".candidate" + suffix)
            candidate.write_bytes(original)
            original_info = image_info(candidate)
            if original_info["width"] >= info["width"] and original_info["height"] >= info["height"]:
                path.write_bytes(original)
                image, info, resolved_image, selected_url = original, original_info, original_resolved, origin_url
            candidate.unlink()
        except (OSError, ValueError, subprocess.CalledProcessError):
            pass
    return {"id": identifier, "name": title, "file": path.name, "sourcePage": page,
            "sourceProductID": source_identifier,
            "representation": "official-family" if source_identifier != identifier else "product",
            "resolvedPage": resolved_page, "publishedImageURL": published_url,
            "downloadURL": selected_url, "resolvedImageURL": resolved_image,
            "sha256": hashlib.sha256(image).hexdigest(), "bytes": len(image), **info}


def products():
    catalog = json.loads((ROOT / "LogBatch/Resources/DJI/catalog.json").read_text())
    return sorted({p["slug"]: p["title"] for package in catalog["packages"] for p in package["products"]}.items())


def verify():
    catalog = json.loads((DESTINATION / "manifest.json").read_text())
    assert {p["id"] for p in catalog["products"]} == {identifier for identifier, _ in products()}
    for product in catalog["products"]:
        path = DESTINATION / product["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == product["sha256"], product["id"]
        info = image_info(path)
        assert all(info[key] == product[key] for key in info), product["id"]
    print(json.dumps({"productImages": len(catalog["products"]), "verified": True}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    if not args.download:
        verify()
        return
    if (DESTINATION / "manifest.json").exists():
        parser.error("Artwork is pinned. Use a reviewed migration for updates.")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    results, errors = [], []
    previous_report = DESTINATION / "import-report.json"
    resumed = {}
    if previous_report.exists():
        for product in json.loads(previous_report.read_text())["products"]:
            path = DESTINATION / product["file"]
            if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == product["sha256"]:
                product.setdefault("sourceProductID", product["id"])
                product.setdefault("representation", "product")
                resumed[product["id"]] = product
    results.extend(resumed.values())
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(load_product, product): product for product in products() if product[0] not in resumed}
        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result()
                results.append(result)
                print(result["id"], result["width"], result["height"], flush=True)
            except Exception as error:
                errors.append({"id": futures[future][0], "error": str(error)})
                print(errors[-1], flush=True)
    report = {"schemaVersion": 1, "checkedAt": "2026-10-30", "redistributionPermission": "unverified",
              "products": sorted(results, key=lambda p: p["id"]), "errors": errors}
    name = "manifest.json" if not errors else "import-report.json"
    (DESTINATION / name).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if errors:
        raise SystemExit(1)
    (DESTINATION / "import-report.json").unlink(missing_ok=True)
    verify()


if __name__ == "__main__":
    main()
