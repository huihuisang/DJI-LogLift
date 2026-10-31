#!/usr/bin/env python3
"""Inspect encoded output independently from AVFoundation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)
    ]))


def audio_hash(path):
    data = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
                                    "-c", "copy", "-f", "adts", "-"])
    return hashlib.sha256(data).hexdigest()


source_audio = audio_hash(root / "synthetic.mp4")
report = {}
for filename in ("identity-rec709.mp4", "nano-rec709.mp4"):
    info = probe(root / filename)
    video = next(s for s in info["streams"] if s["codec_type"] == "video")
    assert video["codec_name"] == "hevc"
    assert video["pix_fmt"] == "yuv420p10le", video
    assert video["color_primaries"] == video["color_transfer"] == video["color_space"] == "bt709", video
    assert video["width"] == 320 and video["height"] == 180
    assert video["nb_frames"] == "24", video
    assert abs(float(info["format"]["duration"]) - 1) <= 0.05
    assert audio_hash(root / filename) == source_audio
    report[filename] = {"codec": video["codec_name"], "pixelFormat": video["pix_fmt"],
                        "primaries": video["color_primaries"], "transfer": video["color_transfer"],
                        "matrix": video["color_space"], "frames": video["nb_frames"],
                        "duration": info["format"]["duration"], "audioUnchanged": True}

# Compare decoded RGB samples with an identity LUT. Codec differences are expected;
# a second gamma transform would cause a much larger error across the frame.
def pixels(name):
    return subprocess.check_output(["ffmpeg", "-v", "error", "-noautorotate", "-i", str(root / name),
                                    "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])

original = pixels("synthetic-rotated.mp4")
converted = pixels("identity-rec709.mp4")
assert len(original) == len(converted)
mae = sum(abs(a - b) for a, b in zip(original, converted)) / len(original)
assert mae < 5, f"Identity transform RGB mean absolute error: {mae}"
report["identityRGBMeanAbsoluteError"] = mae
print(json.dumps(report, indent=2))

