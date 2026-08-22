#!/usr/bin/env python3
"""Process AI-generated entity sprite sheets: chroma-key magenta bg, remove watermark.
For the wall tile, fill transparent edges with stone color to keep it opaque."""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from chroma_key import chroma_key

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MAPPING = {
    # source_basename_keyword: (subdir_glob, final_name, is_wall)
    "seamless_medieval_stone_cast": ("wall.png", True),
    "steampunk_cannon_turret_base": ("turret_base.png", False),
    "sprite_sheet__4_frames_horiz_2026-08-22T13-24-35": ("turret_barrel.png", False),
    "sprite_sheet__4_frames_horiz_2026-08-22T13-24-37": ("production.png", False),
    "sprite_sheet__4_frames_horiz_2026-08-22T13-25-15": ("core.png", False),
    "sprite_sheet__4_frames_horiz_2026-08-22T13-25-16": ("zombie_walker.png", False),
    "sprite_sheet__4_frames_horiz_2026-08-22T13-25-12": ("zombie_runner.png", False),
    "sprite_sheet__4_frames_horiz_2026-08-22T13-25-18": ("zombie_spitter.png", False),
}


def find_source(keyword: str) -> str:
    for root, _, files in os.walk(os.path.join(ROOT, "assets", "sheets", "gen_new")):
        for f in files:
            if f.endswith(".png") and keyword in f:
                return os.path.join(root, f)
    raise FileNotFoundError(f"No generated png matches keyword {keyword}")


def fill_transparent_with_opaque_color(img: Image.Image) -> Image.Image:
    """Replace fully-transparent pixels with the average opaque color."""
    arr = np.array(img.convert("RGBA"))
    a = arr[:, :, 3]
    opaque_mask = a > 128
    if not np.any(opaque_mask):
        return img
    mean_color = np.mean(arr[opaque_mask, :3], axis=0).astype(np.uint8)
    arr[~opaque_mask] = np.concatenate([mean_color, [255]])  # fully opaque
    return Image.fromarray(arr)


def process_all() -> None:
    out_dir = os.path.join(ROOT, "assets", "sheets")
    os.makedirs(out_dir, exist_ok=True)

    for keyword, (final_name, is_wall) in MAPPING.items():
        src = find_source(keyword)
        tmp = os.path.join(ROOT, "tmp_chroma.png")
        print(f"Processing {final_name} from {os.path.basename(src)}")

        # Remove magenta background and bottom-right watermark aggressively.
        # The watermark is consistently light text in the bottom-right corner.
        chroma_key(src, tmp, bg_hex="ff00ff", watermark_w=220, watermark_h=100,
                   color_threshold=100, white_threshold=130)

        img = Image.open(tmp).convert("RGBA")
        w, h = img.size

        # For 4-frame sheets the watermark sits in the right margin of the last frame.
        # Crop the rightmost 64px to move it outside the visible frame area (frame width becomes w/4).
        if w >= 1024:
            img = img.crop((0, 0, w - 64, h))
            w, h = img.size

        # Hard-blank the very bottom-right corner where any residual watermark lingers.
        pix = img.load()
        for y in range(max(0, h - 80), h):
            for x in range(max(0, w - 160), w):
                pix[x, y] = (0, 0, 0, 0)

        if is_wall:
            img = fill_transparent_with_opaque_color(img)

        dst = os.path.join(out_dir, final_name)
        img.save(dst, "PNG")
        print(f"  -> {dst} size={img.size} mode={img.mode}")

        # Verify
        arr = np.array(img)
        opaque = int((arr[:, :, 3] > 128).sum())
        trans = int((arr[:, :, 3] < 20).sum())
        total = arr.shape[0] * arr.shape[1]
        print(f"  opaque={opaque} ({100*opaque/total:.1f}%) trans={trans} ({100*trans/total:.1f}%)")

    os.remove(tmp)
    print("Done.")


if __name__ == "__main__":
    process_all()
