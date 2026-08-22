#!/usr/bin/env python3
"""Process AI-generated UI icons: chroma-key magenta bg + remove bottom-right watermark."""
import os
import sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from chroma_key import chroma_key

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_GEN = os.path.join(ROOT, "assets", "ui", "gen_new")

# Map final filename -> (source_keyword_or_path, subdir_hint)
# For dirs with a single png, just the dir name is enough.
UI_FILES = {
    "btn_wall.png":       ("wall/raw.png", None),
    "btn_defense.png":    ("defense/raw.png", None),
    "btn_production.png": ("production/raw.png", None),
    "btn_core.png":       ("core/raw.png", None),
    "btn_upgrade.png":    ("upgrade/A_polished", None),
    "btn_clear.png":      ("clear/A_polished_mobile_strategy_gam_2026-08-22T13-16-17", None),
    "btn_save.png":       ("save/A_polished", None),
    "btn_load.png":       ("zombie_spitter/A_polished_mobile_strategy_gam_2026-08-22T13-34-16", None),
    "btn_zombie_walker.png": ("zombie_walker/A_polished", None),
    "btn_zombie_runner.png": ("zombie_spitter/A_polished_mobile_strategy_gam_2026-08-22T13-34-17", None),
    "btn_zombie_spitter.png": ("zombie_spitter/A_polished_mobile_strategy_gam_2026-08-22T13-34-20", None),
    "btn_weather_clear.png": ("weather_rain/A_polished_mobile_strategy_gam_2026-08-22T13-34-35", None),
    "btn_weather_rain.png":  ("weather_rain/A_polished_mobile_strategy_gam_2026-08-22T13-34-36", None),
    "btn_weather_snow.png":  ("weather_snow/A_polished", None),
    "btn_mode_attack.png":   ("weather_rain/A_polished_mobile_strategy_gam_2026-08-22T13-34-29", None),
    "btn_mode_editor.png":   ("weather_rain/A_polished_mobile_strategy_gam_2026-08-22T13-34-31", None),
}


def find_source(keyword: str) -> str:
    """Locate the unique generated png matching the keyword."""
    parts = keyword.split("/")
    if len(parts) == 2:
        subdir, kw = parts
        search_root = os.path.join(UI_GEN, subdir)
    else:
        kw = parts[0]
        search_root = UI_GEN
    if not os.path.isdir(search_root):
        raise FileNotFoundError(f"No gen dir {search_root}")
    candidates = []
    for f in os.listdir(search_root):
        if f.endswith(".png") and kw in f:
            candidates.append(os.path.join(search_root, f))
    if len(candidates) == 0:
        raise FileNotFoundError(f"No png matching '{keyword}' in {search_root}")
    if len(candidates) > 1:
        raise ValueError(f"Multiple pngs match '{keyword}': {candidates}")
    return candidates[0]


def process_all() -> None:
    out_dir = os.path.join(ROOT, "assets", "ui")
    os.makedirs(out_dir, exist_ok=True)
    tmp = os.path.join(ROOT, "tmp_ui_chroma.png")

    for final_name, (keyword, _) in UI_FILES.items():
        src = find_source(keyword)
        print(f"Processing {final_name} from {os.path.basename(src)}")

        # Icons are 512x512, watermark is bottom-right ~160x70.
        # Use strong white detection to remove watermark, but keep color_threshold
        # moderate so bright golden highlights survive.
        chroma_key(src, tmp, bg_hex="ff00ff", watermark_w=180, watermark_h=80,
                   color_threshold=90, white_threshold=145)

        img = Image.open(tmp).convert("RGBA")
        w, h = img.size

        # Hard-blank bottom-right corner to ensure watermark is gone.
        pix = img.load()
        for y in range(max(0, h - 80), h):
            for x in range(max(0, w - 180), w):
                pix[x, y] = (0, 0, 0, 0)

        dst = os.path.join(out_dir, final_name)
        img.save(dst, "PNG")

        arr = np.array(img)
        opaque = int((arr[:, :, 3] > 128).sum())
        trans = int((arr[:, :, 3] < 20).sum())
        total = arr.shape[0] * arr.shape[1]
        print(f"  -> {dst} opaque={opaque} ({100*opaque/total:.1f}%) trans={trans} ({100*trans/total:.1f}%)")

    os.remove(tmp)
    print("Done.")


if __name__ == "__main__":
    process_all()
