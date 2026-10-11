"""Pack the rendered RGBA frames without resampling or a background matte."""
from pathlib import Path
import argparse
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("frames", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
for mood in range(10):
    atlas = Image.new("RGBA", (3328, 3328))
    for index in range(169):
        with Image.open(args.frames / str(mood) / f"frame-{index:04d}.png") as frame:
            if frame.mode != "RGBA" or frame.size != (256, 251):
                raise ValueError(f"Unexpected frame format: {mood}/{index}")
            atlas.paste(frame, ((index % 13) * 256, (index // 13) * 256 + 2))
    atlas.save(args.output / f"{mood}.png", optimize=True)
