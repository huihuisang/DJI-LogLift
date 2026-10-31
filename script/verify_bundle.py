#!/usr/bin/env python3
"""Check the actual app bundle, including its embedded resource framework."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys

project = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1])
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert app.name == "LogLift for DJI.app", app
assert info["CFBundleDisplayName"] == "LogLift for DJI", info
assert info["CFBundleName"] == "LogLift for DJI", info
assert info["CFBundleExecutable"] == "LogLift", info
assert info["CFBundleIdentifier"] == "dev.logbatch.app", info
assert (app / "Contents/MacOS" / info["CFBundleExecutable"]).is_file()
assert "CFBundleDocumentTypes" not in info, info
assert info["CFBundleURLTypes"] == [{
    "CFBundleURLName": "dev.logbatch.import", "CFBundleTypeRole": "Viewer", "CFBundleURLSchemes": ["loglift"]
}], info
extension = app / "Contents/PlugIns/LogLiftFinderExtension.appex"
extension_info = plistlib.loads((extension / "Contents/Info.plist").read_bytes())
assert extension_info["CFBundleIdentifier"] == "dev.logbatch.app.FinderExtension", extension_info
assert extension_info["CFBundleVersion"] == info["CFBundleVersion"], extension_info
assert extension_info["CFBundleShortVersionString"] == info["CFBundleShortVersionString"], extension_info
assert extension_info["NSExtension"] == {
    "NSExtensionPointIdentifier": "com.apple.FinderSync",
    "NSExtensionPrincipalClass": "LogLiftFinderExtension.FinderSync",
}, extension_info
assert not (extension / "Contents/Frameworks/LogBatchCore.framework").exists()
for locale, title in {"en": "Import into LogLift", "zh-Hans": "导入 LogLift",
                      "ja": "LogLift に読み込む", "ko": "LogLift로 가져오기"}.items():
    strings = json.loads(subprocess.check_output([
        "/usr/bin/plutil", "-convert", "json", "-o", "-",
        str(extension / ("Contents/Resources/" + locale + ".lproj/Localizable.strings"))
    ]))
    assert strings["Import into LogLift"] == title, (locale, strings)
    assert strings["LogLift could not be opened."], locale
assert info["CFBundleIconName"] == "AppIcon", info
icon_file = info["CFBundleIconFile"]
icon_path = app / "Contents/Resources" / icon_file
if not icon_path.suffix:
    icon_path = icon_path.with_suffix(".icns")
icon_data = icon_path.read_bytes()
assert icon_data[:4] == b"icns", icon_path
assert struct.unpack(">I", icon_data[4:8])[0] == len(icon_data), icon_path
icon_source = project / "LogBatch/Resources/Assets.xcassets/AppIcon.appiconset"
menu_icon = extension / "Contents/Resources/FinderAppIcon.png"
menu_icon_data = menu_icon.read_bytes()
assert menu_icon_data == (project / "FinderExtension/Resources/FinderAppIcon.png").read_bytes()
assert menu_icon_data[:8] == b"\x89PNG\r\n\x1a\n"
assert struct.unpack(">II", menu_icon_data[16:24]) == (32, 32)
assert menu_icon_data[24:26] == bytes((8, 6)), "Menu artwork must retain its RGBA channels."
icon_images = json.loads((icon_source / "Contents.json").read_text())["images"]
assert {(image["size"], image["scale"]) for image in icon_images} == {
    (f"{size}x{size}", f"{scale}x")
    for size in (16, 32, 128, 256, 512) for scale in (1, 2)
}
for image in icon_images:
    image_path = icon_source / image["filename"]
    png = image_path.read_bytes()
    assert image["idiom"] == "mac", image
    assert png[:8] == b"\x89PNG\r\n\x1a\n", image_path
    pixels = int(image["size"].split("x")[0]) * int(image["scale"][0])
    assert struct.unpack(">II", png[16:24]) == (pixels, pixels), image_path
asset_info = json.loads(subprocess.check_output([
    "/usr/bin/xcrun", "assetutil", "--info", str(app / "Contents/Resources/Assets.car")
]))
compiled_icons = [asset for asset in asset_info
                  if asset.get("Name") == "AppIcon" and asset.get("AssetType") == "Icon Image"]
assert len(compiled_icons) == len(icon_images), compiled_icons
for image in icon_images:
    pixels = int(image["size"].split("x")[0]) * int(image["scale"][0])
    matches = [asset for asset in compiled_icons if asset["RenditionName"] == image["filename"]]
    assert len(matches) == 1, image
    assert (matches[0]["PixelWidth"], matches[0]["PixelHeight"]) == (pixels, pixels), image
framework = app / "Contents/Frameworks/LogBatchCore.framework/Resources"
root = framework / "DJI"
catalog = json.loads((root / "catalog.json").read_text())
assert (root / "catalog.json").read_bytes() == (project / "LogBatch/Resources/DJI/catalog.json").read_bytes()
luts = [lut for package in catalog["packages"] for lut in package["luts"]]
for lut in luts:
    data = (root / lut["file"]).read_bytes()
    assert hashlib.sha256(data).hexdigest() == lut["sha256"], lut["id"]
for owner in (app / "Contents/Resources", framework):
    for locale in ("en", "zh-Hans", "ja", "ko"):
        strings_path = owner / (locale + ".lproj/Localizable.strings")
        assert strings_path.is_file(), (owner, locale)
        if owner == app / "Contents/Resources":
            strings = json.loads(subprocess.check_output(
                ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(strings_path)]))
            assert strings["LogLift for DJI"] == "LogLift for DJI", locale
            assert "LogBatch" not in strings, locale
artwork_root = app / "Contents/Resources/ProductImages"
artwork = json.loads((artwork_root / "manifest.json").read_text())
assert {p["id"] for p in artwork["products"]} == {p["slug"] for package in catalog["packages"] for p in package["products"]}
for product in artwork["products"]:
    assert hashlib.sha256((artwork_root / product["file"]).read_bytes()).hexdigest() == product["sha256"]
print(json.dumps({"appName": info["CFBundleDisplayName"], "executable": info["CFBundleExecutable"],
                  "bundleIdentifier": info["CFBundleIdentifier"],
                  "appIcon": {"name": info["CFBundleIconName"], "file": icon_path.name,
                              "sourceImages": len(icon_images),
                              "compiledImages": len(compiled_icons),
                              "sha256": hashlib.sha256(icon_data).hexdigest()},
                  "bundledPackages": len(catalog["packages"]), "bundledCubes": len(luts),
                  "productImages": len(artwork["products"]),
                  "finderExtension": extension_info["CFBundleIdentifier"],
                  "finderMenuIcon": menu_icon.name,
                  "localizedTargets": 3, "locales": ["en", "zh-Hans", "ja", "ko"]}, indent=2))

