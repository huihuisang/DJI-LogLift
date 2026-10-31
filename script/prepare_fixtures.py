#!/usr/bin/env python3
"""Generate synthetic verification inputs; no user media is read."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)


def ffmpeg(*arguments):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-n", *map(str, arguments)], check=True)


ffmpeg("-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=1", "-f", "lavfi", "-i",
       "sine=frequency=440:sample_rate=48000:duration=1", "-c:v", "libx265", "-preset", "ultrafast",
       "-x265-params", "log-level=error", "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1", "-c:a", "aac",
       "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", root / "synthetic.mp4")
ffmpeg("-display_rotation:v:0", "90", "-i", root / "synthetic.mp4", "-c", "copy", root / "synthetic-rotated.mp4")
rotation = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                    "stream_side_data=rotation", "-of", "csv=p=0", str(root / "synthetic-rotated.mp4")])
assert rotation.strip() == b"90", "The fixture must contain an actual rotation matrix"
for angle in (0, 90, 180, 270):
    for mirrored in (False, True):
        flip = ["-display_hflip:v:0"] if mirrored else []
        ffmpeg("-display_rotation:v:0", angle, *flip,
               "-i", root / "synthetic.mp4", "-c", "copy",
               root / f"synthetic-orientation-{angle}-{str(mirrored).lower()}.mp4")
ffmpeg("-i", root / "synthetic.mp4", "-c", "copy", "-color_primaries", "bt2020", "-color_trc", "arib-std-b67",
       "-colorspace", "bt2020nc", "-bsf:v", "hevc_metadata=colour_primaries=9:transfer_characteristics=18:matrix_coefficients=9",
       root / "synthetic-hlg.mp4")
ffmpeg("-i", root / "synthetic.mp4", "-map", "0:v:0", "-map", "0:v:0", "-map", "0:a:0",
       "-c", "copy", root / "synthetic-multitrack.mp4")
ffmpeg("-i", root / "synthetic.mp4", "-c", "copy",
       "-metadata", "creation_time=2026-10-29T02:30:00Z", root / "synthetic-created.mp4")
shutil.copyfile(root / "synthetic.mp4", root / "DJI_20261030121350_0207_D.MP4")

