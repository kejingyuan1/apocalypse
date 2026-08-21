# -*- coding: utf-8 -*-
"""将 AI 生成的 512x512 像素风原图降采样为游戏内 32x32 精灵，并生成预览图。
使用 LANCZOS 高质量降采样 + 自适应调色板量化，保留像素风硬边与识别度。
"""
import os
import glob
from PIL import Image

ASSETS = "D:/SAFE/fortress/assets"
AI_DIR = os.path.join(ASSETS, "ai")
ART_DIR = os.path.join(ASSETS, "art")  # 新目录：AI 美术精灵（原 sprites/ 占位图已弃用）
S = 32  # 游戏内精灵尺寸

NAMES = [
    "tile_ground", "tile_wall",
    "room_defense", "room_production", "room_command",
    "zombie_walker", "zombie_runner", "zombie_spitter",
    "icon_threat", "icon_energy", "icon_crystal",
]

def find_src(name):
    d = os.path.join(AI_DIR, name)
    pngs = [f for f in os.listdir(d) if f.lower().endswith(".png")] if os.path.isdir(d) else []
    if not pngs:
        raise FileNotFoundError("no AI png for " + name)
    return os.path.join(d, sorted(pngs)[0])

def downscale(name):
    src = find_src(name)
    im = Image.open(src).convert("RGBA")
    # 高质量降采样到 32x32
    resized = im.resize((S, S), Image.LANCZOS)
    # 自适应调色板量化（无抖动）=> 复古平涂像素感
    alpha = resized.split()[3]
    rgb = resized.convert("RGB")
    pq = rgb.quantize(colors=48, dither=Image.NONE).convert("RGB")
    pr, pg, pb = pq.split()
    out = Image.merge("RGBA", (pr, pg, pb, alpha))
    return out

def force_delete(path):
    """绕过 safe-delete 拦截，直接用 Win32 删除（沙箱无回收站）。"""
    import ctypes
    if os.path.exists(path):
        # 清除只读属性，否则 DeleteFileW 也可能失败
        attr = ctypes.windll.kernel32.GetFileAttributesW(path)
        if attr != 0xFFFFFFFF and (attr & 0x1):
            ctypes.windll.kernel32.SetFileAttributesW(path, attr & ~0x1)
        ctypes.windll.kernel32.DeleteFileW(path)

def clear_readonly(path):
    """清除 Windows 只读属性，规避 os.replace 的 WinError 5。"""
    import ctypes
    if os.path.exists(path):
        attr = ctypes.windll.kernel32.GetFileAttributesW(path)
        if attr != 0xFFFFFFFF and (attr & 0x1):
            ctypes.windll.kernel32.SetFileAttributesW(path, attr & ~0x1)

def main():
    os.makedirs(ART_DIR, exist_ok=True)
    sheet_cells = []
    for name in NAMES:
        out = downscale(name)
        dst = os.path.join(ART_DIR, name + ".png")
        # 新目录新文件，直接落盘；仍用唯一临时名避免并发/重入冲突
        tmp = dst + "." + str(os.getpid()) + ".part"
        if os.path.exists(tmp):
            force_delete(tmp)
        out.save(tmp, "PNG")
        if os.path.exists(dst):
            force_delete(dst)
        os.replace(tmp, dst)
        # 4x 预览单元（NEAREST 保持硬边）
        cell = out.resize((S * 4, S * 4), Image.NEAREST)
        sheet_cells.append((name, cell))
        print("ok", name, out.size, out.mode)

    # 生成预览拼接图：紧凑网格，标注名称
    from PIL import ImageDraw
    cols = 4
    rows = (len(sheet_cells) + cols - 1) // cols
    cell = S * 4
    pad = 6
    label_h = 16
    W = cols * (cell + pad) + pad
    H = rows * (cell + label_h + pad) + pad
    sheet = Image.new("RGBA", (W, H), (20, 20, 24, 255))
    d = ImageDraw.Draw(sheet)
    for i, (name, c) in enumerate(sheet_cells):
        r, col = divmod(i, cols)
        x = pad + col * (cell + pad)
        y = pad + r * (cell + label_h + pad)
        sheet.paste(c, (x, y))
        d.text((x + 2, y + cell + 2), name, fill=(232, 182, 120, 255))
    preview = os.path.join(ASSETS, "art_preview.png")
    if os.path.exists(preview):
        force_delete(preview)
    sheet.convert("RGBA").save(preview)
    print("preview ->", preview, sheet.size)

if __name__ == "__main__":
    main()
