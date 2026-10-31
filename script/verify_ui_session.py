#!/usr/bin/env python3
"""Verify files produced by a foreground UI session without controlling the app."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)
    ]))


def audio_hash(path):
    audio = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0", "-c", "copy", "-f", "adts", "-"
    ])
    return hashlib.sha256(audio).hexdigest()


def verify(root, output_name, ui_state):
    baseline = json.loads((root / "Checks/input-hashes.json").read_text())
    outputs = root / output_name
    assert {p.name for p in outputs.glob("*.mp4")} == {
        Path(name).stem + "-rec709.mp4" for name in baseline
    }
    assert not list(outputs.glob(".logbatch-*")), "A temporary export remains"
    state = json.loads(ui_state.read_text())
    assert state["completedRows"] == len(baseline)
    assert state["conversionEnabled"] is False
    report = {"clips": [], "ui": state}
    for name, checksum in baseline.items():
        source = root / "Input" / name
        destination = outputs / (source.stem + "-rec709.mp4")
        assert hashlib.sha256(source.read_bytes()).hexdigest() == checksum, name
        original, converted = probe(source), probe(destination)
        input_video = next(s for s in original["streams"] if s["codec_type"] == "video")
        video = next(s for s in converted["streams"] if s["codec_type"] == "video")
        assert video["codec_name"] == "hevc" and video["pix_fmt"] == "yuv420p10le"
        assert video["color_primaries"] == video["color_transfer"] == video["color_space"] == "bt709"
        for key in ("width", "height", "nb_frames", "avg_frame_rate"):
            assert video[key] == input_video[key], (name, key)
        duration = float(converted["format"]["duration"])
        assert abs(duration - float(original["format"]["duration"])) < 0.05
        assert audio_hash(source) == audio_hash(destination), name
        report["clips"].append({
            "input": name, "output": destination.name,
            "inputSHA256": checksum, "outputSHA256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            "width": video["width"], "height": video["height"], "frames": video["nb_frames"],
            "frameRate": video["avg_frame_rate"], "duration": duration,
            "codec": "hevc", "pixelFormat": "yuv420p10le", "colorSpace": "bt709",
            "originalUnchanged": True, "audioUnchanged": True,
        })
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("demo_root", type=Path)
    parser.add_argument("--output", default="Output-Verified")
    parser.add_argument("--ui-state", type=Path, required=True)
    arguments = parser.parse_args()
    print(json.dumps(verify(arguments.demo_root, arguments.output, arguments.ui_state), ensure_ascii=False, indent=2))
