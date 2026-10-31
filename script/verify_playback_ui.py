#!/usr/bin/env python3
"""Check native playback snapshots and app-only audio/video capture."""
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys


def verify(root):
    hashes = root / "app-source-hashes.json"
    if hashes.exists():
        project = Path(__file__).resolve().parents[1]
        for name, digest in json.loads(hashes.read_text()).items():
            relative = Path(name)
            assert not relative.is_absolute() and ".." not in relative.parts
            assert hashlib.sha256((project / relative).read_bytes()).hexdigest() == digest, name

    def snapshot(name):
        elements = json.loads((root / (name + ".json")).read_text())["elements"]
        controls = {e["id"]: e for e in elements if "id" in e}
        return elements, controls

    def control(name, identifier):
        return snapshot(name)[1][identifier]

    def position(name):
        return float(control(name, "preview-timeline")["value"])

    def paused(name):
        return control(name, "preview-play-pause")["description"] == "播放"

    assert paused("initial-paused") and position("initial-paused") < 0.05
    assert not paused("playing") and position("playing") > 1
    assert paused("paused") and paused("paused-stable")
    assert abs(position("paused") - position("paused-stable")) < 0.01
    assert paused("seek-paused") and abs(position("seek-paused") - 12) < 0.2
    assert not paused("seek-playing") and 4 < position("seek-playing") < 6
    assert not paused("space-playing") and paused("space-paused")
    assert position("space-paused") >= position("space-playing")
    assert paused("seek-end") and abs(position("seek-end") - 20) < 0.05
    assert not paused("replay-from-end") and 0.1 < position("replay-from-end") < 2
    assert paused("final-paused")
    assert control("muted-playing", "preview-mute")["description"] == "取消静音"

    events = [json.loads(line) for line in (root / "events.jsonl").read_text().splitlines()]
    times = {event["name"]: event["wall"] for event in events}
    stats = json.loads((root / "capture-stats.json").read_text())
    assert stats["microphoneCaptured"] is False
    assert stats["videoFrames"] > 100
    audio = {}
    for start, end in zip(events, events[1:]):
        values = [sample["rms"] for sample in stats["audioSamples"]
                  if start["wall"] + 0.35 < sample["wall"] < end["wall"] - 0.15]
        if len(values) > 10:
            rms = math.sqrt(sum(value * value for value in values) / len(values))
            audio[start["name"]] = {"rms": rms, "buffers": len(values)}
    for name in ["playing-unmuted", "resumed-unmuted", "unmuted-playing", "space-playing", "replay-from-end"]:
        assert audio[name]["rms"] > 0.02, (name, audio.get(name))
    for name in ["initial-paused", "paused", "muted-playing", "space-paused"]:
        assert audio[name]["rms"] < 0.00001, (name, audio.get(name))

    movie = root / "playback-acceptance.mp4"
    if not movie.exists():
        movie = root / "foreground-capture-v2.mp4"
    probe = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(movie)
    ]))
    video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
    sound = next(stream for stream in probe["streams"] if stream["codec_type"] == "audio")
    assert video["width"] == 1280 and video["height"] == 900
    assert int(sound["sample_rate"]) == 48000 and sound["channels"] == 2
    assert float(probe["format"]["duration"]) >= 25

    offset = times["playing-unmuted"] - stats["firstFrameWall"] + 0.5
    pcm = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", str(offset), "-i", str(movie), "-t", "0.5",
        "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"
    ])
    samples = array.array("f")
    samples.frombytes(pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    assert len(samples) > 10000
    window = [value * (0.5 - 0.5 * math.cos(2 * math.pi * i / (len(samples) - 1)))
              for i, value in enumerate(samples)]

    def tone_power(frequency):
        coefficient = 2 * math.cos(2 * math.pi * frequency / 48000)
        previous = older = 0.0
        for value in window:
            current = value + coefficient * previous - older
            older, previous = previous, current
        return previous * previous + older * older - coefficient * previous * older

    peak = max(range(425, 456), key=tone_power)
    assert abs(peak - 440) <= 1, peak

    elements, controls = snapshot("initial-paused")
    window_frame = next(e["frame"] for e in elements if e["role"] == "AXWindow")
    preview = controls["comparison-handle"]["frame"]
    crop = [int(preview[2] - 24), int(preview[3] - 100),
            int(preview[0] - window_frame[0] + 12), int(preview[1] - window_frame[1] + 35)]

    def pixels(wall):
        time = max(0, wall - stats["firstFrameWall"])
        return subprocess.check_output([
            "ffmpeg", "-v", "error", "-ss", str(time), "-i", str(movie), "-frames:v", "1",
            "-vf", "crop=%d:%d:%d:%d,scale=128:80,format=rgb24" % tuple(crop), "-f", "rawvideo", "-"
        ])

    def error(first, second):
        assert len(first) == len(second) == 128 * 80 * 3
        return sum(abs(a - b) for a, b in zip(first, second)) / len(first)

    moving = error(pixels(times["playing-unmuted"] + 0.35), pixels(times["playing-unmuted"] + 1.35))
    stopped = error(pixels(times["paused"] + 0.35), pixels(times["paused"] + 0.9))
    seeking = error(pixels(times["paused"] + 0.9), pixels(times["seek-paused"] + 0.1))
    assert moving > 1, moving
    assert stopped < 1.5, stopped
    assert seeking > 1, seeking
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(movie), "-fps_mode", "passthrough",
                    "-enc_time_base", "demux", "-f", "null", "-"], check=True)
    return {"verified": True, "playback": True, "pause": True, "pausedSeek": True,
            "playingSeekResumes": True, "spaceKey": True, "endAndReplay": True,
            "audioTonePeakHz": peak, "audioStates": audio,
            "videoPixelErrors": {"playing": moving, "paused": stopped, "afterSeek": seeking},
            "microphoneCaptured": False, "duration": float(probe["format"]["duration"]),
            "movieSHA256": hashlib.sha256(movie.read_bytes()).hexdigest()}


if __name__ == "__main__":
    print(json.dumps(verify(Path(sys.argv[1])), indent=2))
