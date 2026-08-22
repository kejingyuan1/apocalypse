#!/usr/bin/env python3
"""Remove a solid chroma background + bottom-right watermark from AI-generated images.

Uses color distance to build an initial mask, then flood-fills from the corners
to remove any background-connected fringe (magenta shadow / checkerboard / watermark).

Usage:
    python chroma_key.py <input.png> <output.png> [hex_bg] [watermark_w] [watermark_h]

Defaults:
    hex_bg = ff00ff (magenta)
    watermark_w = 160, watermark_h = 70
"""

import sys
from collections import deque
from PIL import Image
import numpy as np


def chroma_key(
    src_path: str,
    dst_path: str,
    bg_hex: str = "ff00ff",
    watermark_w: int = 160,
    watermark_h: int = 70,
    color_threshold: int = 90,
    white_threshold: int = 160,
) -> None:
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    data = np.array(img)
    r, g, b, a = data[:, :, 0], data[:, :, 1], data[:, :, 2], data[:, :, 3]

    bg_r = int(bg_hex[0:2], 16)
    bg_g = int(bg_hex[2:4], 16)
    bg_b = int(bg_hex[4:6], 16)

    # 1. Identify "background" pixels: transparent, close to bg color, or white watermark
    dr = r.astype(np.float32) - bg_r
    dg = g.astype(np.float32) - bg_g
    db = b.astype(np.float32) - bg_b
    dist_bg = np.sqrt(dr * dr + dg * dg + db * db)

    # light/white pixels (watermark text)
    lightness = (r.astype(np.int16) + g.astype(np.int16) + b.astype(np.int16)) / 3.0
    is_white = (lightness > white_threshold) & (r > white_threshold) & (g > white_threshold) & (b > white_threshold)

    bg_mask = (a < 20) | (dist_bg < color_threshold) | is_white

    # 2. Restrict white detection to bottom-right watermark region, so we don't erase bright foreground.
    wm_x1 = max(0, w - watermark_w)
    wm_y1 = max(0, h - watermark_h)
    white_mask = np.zeros_like(bg_mask)
    white_mask[wm_y1:h, wm_x1:w] = is_white[wm_y1:h, wm_x1:w]
    bg_mask = (a < 20) | (dist_bg < color_threshold) | white_mask

    # 3. Flood fill through all background pixels.
    #    Starting from all background seeds guarantees even enclosed magenta pockets
    #    (between frames, inside shapes) get removed.
    visited = np.zeros_like(bg_mask)
    q = deque()
    for sy, sx in zip(*np.where(bg_mask)):
        visited[sy, sx] = True
        q.append((sx, sy))

    while q:
        x, y = q.popleft()
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny, nx] and bg_mask[ny, nx]:
                visited[ny, nx] = True
                q.append((nx, ny))

    # 4. Keep only non-background-connected pixels
    keep = ~visited
    data[~keep] = [0, 0, 0, 0]

    out = Image.fromarray(data)
    out.save(dst_path, "PNG")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]
    bg = sys.argv[3] if len(sys.argv) > 3 else "ff00ff"
    ww = int(sys.argv[4]) if len(sys.argv) > 4 else 160
    wh = int(sys.argv[5]) if len(sys.argv) > 5 else 70
    chroma_key(src, dst, bg, ww, wh)
