# -*- coding: utf-8 -*-
"""
末日堡垒 . 像素美术生成器
按美术圣经调色板生成 32x32 像素精灵，保存到 fortress/assets/sprites/
调色板（美术圣经 v0.2）：
  AMBER_WARM   #E8923D   暖橙（主色/生产）
  ENERGY_CYAN  #48B6E8   能源青
  DANGER_ORANGE#E8762E   威胁橙（单层暖橙铁律，唯一威胁色）
  ZOMBIE_SKIN  #6E7A55   丧尸肤色
"""
from PIL import Image, ImageDraw

S = 32  # tile size

AMBER   = (0xE8, 0x92, 0x3D)
CYAN    = (0x48, 0xB6, 0xE8)
DANGER  = (0xE8, 0x76, 0x2E)
ZSKIN   = (0x6E, 0x7A, 0x55)
ZSKIN_D = (0x52, 0x5C, 0x40)
OUTLINE = (0x1A, 0x17, 0x12)
WHITE   = (0xED, 0xE6, 0xD8)
GROUND  = (0x3A, 0x33, 0x26)
GROUND2 = (0x4A, 0x40, 0x30)
STONE   = (0x6B, 0x6B, 0x73)
STONE_L = (0x8A, 0x8A, 0x92)
STONE_D = (0x4A, 0x4A, 0x50)
METAL   = (0x45, 0x45, 0x4F)
METAL_D = (0x2E, 0x2E, 0x36)
METAL_L = (0x5E, 0x5E, 0x68)
OLIVE   = (0x7E, 0x88, 0x56)
CRYSTAL = (0x9A, 0xD7, 0xF0)
BLOOD   = (0x7A, 0x3B, 0x33)


def new_img():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def rect(d, x, y, w, h, color):
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def px(d, x, y, color):
    d.point((x, y), fill=color)


def outline_all(img, d, color=OUTLINE):
    snap = img.load()
    for y in range(S):
        for x in range(S):
            if snap[x, y][3] == 0:
                nb = False
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < S and 0 <= ny < S and snap[nx, ny][3] != 0:
                        nb = True
                        break
                if nb:
                    d.point((x, y), fill=color)


def sprite_ground():
    img, d = new_img()
    rect(d, 0, 0, S, S, GROUND)
    for (x, y) in [(4, 6), (9, 3), (14, 10), (21, 5), (26, 14), (7, 20), (18, 23), (24, 27), (12, 17), (29, 9)]:
        rect(d, x, y, 2, 2, GROUND2)
    return img


def sprite_wall():
    img, d = new_img()
    rect(d, 2, 2, 28, 28, STONE)
    rect(d, 2, 2, 28, 3, STONE_L)
    rect(d, 2, 27, 28, 3, STONE_D)
    for y in (11, 20):
        rect(d, 2, y, 28, 1, STONE_D)
    for x in (10, 20):
        rect(d, x, 2, 1, 9, STONE_D)
        rect(d, x + 5, 11, 1, 9, STONE_D)
    outline_all(img, d)
    return img


def sprite_defense():
    img, d = new_img()
    rect(d, 4, 8, 24, 22, METAL_D)
    rect(d, 4, 8, 24, 3, METAL_L)
    rect(d, 11, 6, 10, 10, METAL)
    rect(d, 13, 8, 6, 6, METAL_L)
    rect(d, 15, 2, 4, 8, CYAN)
    rect(d, 15, 2, 4, 2, (0x8E, 0xE0, 0xF5))
    px(d, 8, 24, CYAN); px(d, 23, 24, CYAN)
    outline_all(img, d)
    return img


def sprite_production():
    img, d = new_img()
    rect(d, 4, 6, 24, 24, METAL_D)
    rect(d, 4, 6, 24, 3, METAL_L)
    rect(d, 10, 12, 12, 12, AMBER)
    rect(d, 13, 9, 6, 18, AMBER)
    rect(d, 9, 13, 18, 6, AMBER)
    rect(d, 13, 13, 6, 6, METAL_D)
    outline_all(img, d)
    return img


def sprite_command():
    img, d = new_img()
    rect(d, 4, 6, 24, 24, METAL_D)
    rect(d, 4, 6, 24, 3, METAL_L)
    rect(d, 15, 8, 2, 20, WHITE)
    rect(d, 17, 9, 10, 8, WHITE)
    px(d, 20, 11, AMBER); px(d, 22, 12, AMBER); px(d, 21, 13, AMBER); px(d, 22, 14, AMBER)
    outline_all(img, d)
    return img


def _zombie(base, extra=None):
    img, d = new_img()
    rect(d, 10, 12, 12, 16, base)
    rect(d, 10, 12, 12, 3, ZSKIN)
    rect(d, 10, 25, 12, 3, ZSKIN_D)
    rect(d, 12, 4, 8, 8, base)
    rect(d, 12, 4, 8, 2, ZSKIN)
    px(d, 14, 7, OUTLINE); px(d, 17, 7, OUTLINE)
    rect(d, 6, 14, 4, 10, base)
    rect(d, 22, 14, 4, 10, base)
    if extra:
        extra(d)
    outline_all(img, d)
    return img


def sprite_walker():
    return _zombie(ZSKIN)


def sprite_runner():
    img, d = new_img()
    rect(d, 11, 11, 10, 18, ZSKIN)
    rect(d, 11, 11, 10, 3, ZSKIN)
    rect(d, 11, 26, 10, 3, ZSKIN_D)
    rect(d, 13, 4, 7, 7, ZSKIN)
    rect(d, 13, 4, 7, 2, ZSKIN)
    px(d, 15, 7, OUTLINE); px(d, 18, 7, OUTLINE)
    rect(d, 5, 12, 4, 9, ZSKIN)
    rect(d, 21, 16, 4, 9, ZSKIN)
    outline_all(img, d)
    return img


def sprite_spitter():
    def sac(d):
        rect(d, 20, 14, 8, 10, OLIVE)
        rect(d, 20, 14, 8, 2, (0x9C, 0xA6, 0x6E))
        px(d, 24, 19, BLOOD)
    return _zombie(ZSKIN, extra=sac)


def sprite_threat():
    img, d = new_img()
    for i in range(14):
        rect(d, 16 - i, 6 + i, 2 * i + 1, 1, DANGER)
    rect(d, 3, 19, 26, 3, DANGER)
    rect(d, 3, 21, 26, 9, DANGER)
    rect(d, 15, 8, 2, 8, OUTLINE)
    px(d, 15, 18, OUTLINE)
    outline_all(img, d)
    return img


def sprite_energy():
    img, d = new_img()
    pts = [(18, 3), (10, 17), (15, 17), (12, 29), (23, 12), (17, 12)]
    d.polygon(pts, fill=CYAN)
    d.line([(18, 3), (10, 17), (15, 17), (12, 29), (23, 12), (17, 12), (18, 3)], fill=(0x8E, 0xE0, 0xF5), width=1)
    outline_all(img, d)
    return img


def sprite_crystal():
    img, d = new_img()
    d.polygon([(16, 3), (24, 14), (16, 29), (8, 14)], fill=CRYSTAL)
    d.line([(16, 3), (16, 29)], fill=WHITE, width=1)
    outline_all(img, d)
    return img


SPRITES = {
    "tile_ground.png": sprite_ground,
    "tile_wall.png": sprite_wall,
    "room_defense.png": sprite_defense,
    "room_production.png": sprite_production,
    "room_command.png": sprite_command,
    "zombie_walker.png": sprite_walker,
    "zombie_runner.png": sprite_runner,
    "zombie_spitter.png": sprite_spitter,
    "icon_threat.png": sprite_threat,
    "icon_energy.png": sprite_energy,
    "icon_crystal.png": sprite_crystal,
}

if __name__ == "__main__":
    import os
    out = os.path.join(os.path.dirname(__file__), "sprites")
    os.makedirs(out, exist_ok=True)
    for name, fn in SPRITES.items():
        im = fn()
        path = os.path.join(out, name)
        im.save(path)
        print("saved", path, im.size)
    print("DONE:", len(SPRITES), "sprites")
