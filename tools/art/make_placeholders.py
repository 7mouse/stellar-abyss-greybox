"""从概念图裁出灰盒占位贴图。正式素材按同一路径覆盖即可。

概念图不在仓库里：默认读 /cursor/stores/bot/art/。
"""
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.environ.get("ART_DIR", "/cursor/stores/bot/art")
ACT = os.path.join(ROOT, "assets", "actors")
HUD = os.path.join(ROOT, "assets", "hud")


def _dist(a, bg):
    return np.abs(a.astype(np.int16) - bg.astype(np.int16)).sum(axis=2)


def knock_out(im, thresh=42):
    """从边缘吃掉背景和脚下的浅色影子。角色内部的亮点留着。"""
    a = np.asarray(im.convert("RGB")).astype(np.int16)
    h, w = a.shape[:2]
    bg = a[:2, :2].reshape(-1, 3).mean(axis=0)
    d = _dist(a, bg)
    alpha = np.full((h, w), 255, dtype=np.uint8)
    # 近白、低饱和，并且贴着已经透明的像素：影子和描边
    pale = (d < 78) & ((a.max(axis=2) - a.min(axis=2)) < 42)
    alpha[d < thresh] = 0
    for _ in range(10):
        trans = alpha == 0
        edge = np.zeros((h, w), dtype=bool)
        edge[1:] |= trans[:-1]
        edge[:-1] |= trans[1:]
        edge[:, 1:] |= trans[:, :-1]
        edge[:, :-1] |= trans[:, 1:]
        eat = pale & edge & (alpha > 0)
        if not eat.any():
            break
        alpha[eat] = 0
    rgba = np.dstack([np.clip(a, 0, 255).astype(np.uint8), alpha])
    return Image.fromarray(rgba, "RGBA")


def crop_box(src, box, pad=6):
    im = src.crop(box)
    im = knock_out(im)
    a = np.asarray(im)
    ys, xs = np.where(a[:, :, 3] > 12)
    if len(xs) == 0:
        return im
    x0, x1 = max(0, xs.min() - pad), min(im.width, xs.max() + 1 + pad)
    y0, y1 = max(0, ys.min() - pad), min(im.height, ys.max() + 1 + pad)
    return im.crop((x0, y0, x1, y1))


def circle_crop(im, size=256):
    im = im.resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((1, 1, size - 2, size - 2), fill=255)
    im.putalpha(mask)
    return im


def drop_shadow(im):
    a = np.array(im)
    h = a.shape[0]
    rgb = a[:, :, :3].astype(np.int16)
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    lum = rgb.sum(axis=2)
    y = np.arange(h)[:, None]
    shadow = (y > int(h * 0.7)) & (lum > 400) & (chroma < 60)
    a[:, :, 3][shadow] = 0
    return Image.fromarray(a)


def tighten(im, max_side=160):
    a = np.asarray(im)
    ys, xs = np.where(a[:, :, 3] > 16)
    if len(xs) == 0:
        return im
    im = im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    if max(im.size) > max_side:
        im.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    return im


def save(im, path, max_side=160):
    im = tighten(im, max_side)
    im.save(path)
    print(path, im.size)


def icons():
    def canvas():
        return Image.new("RGBA", (128, 128), (0, 0, 0, 0))

    cream = (236, 226, 206, 255)
    # 轻攻击：一把剑
    im = canvas()
    d = ImageDraw.Draw(im)
    d.line((40, 92, 90, 28), fill=cream, width=12)
    d.polygon([(78, 16), (104, 28), (86, 46)], fill=cream)
    d.line((32, 78, 58, 100), fill=(186, 154, 112, 255), width=10)
    save(im, os.path.join(HUD, "icon_attack.png"))
    # 重攻击：斧
    im = canvas()
    d = ImageDraw.Draw(im)
    d.line((64, 28, 64, 108), fill=(196, 176, 150, 255), width=8)
    d.polygon([(40, 36), (92, 28), (88, 58), (36, 62)], fill=(214, 206, 190, 255))
    save(im, os.path.join(HUD, "icon_heavy.png"))
    # 冲刺
    im = canvas()
    d = ImageDraw.Draw(im)
    d.polygon([(24, 70), (78, 40), (70, 64), (104, 52), (62, 78), (74, 96)], fill=cream)
    save(im, os.path.join(HUD, "icon_dash.png"))
    # 技能 1：紫漩涡
    im = canvas()
    d = ImageDraw.Draw(im)
    d.arc((28, 28, 100, 100), 20, 300, fill=(176, 120, 230, 255), width=10)
    d.arc((44, 44, 84, 84), 200, 500, fill=(210, 170, 255, 255), width=8)
    save(im, os.path.join(HUD, "icon_skill.png"))
    # 技能 2：青光（占位）
    im = canvas()
    d = ImageDraw.Draw(im)
    d.ellipse((40, 40, 88, 88), fill=(120, 230, 220, 255))
    for ang in range(0, 360, 45):
        import math
        a = math.radians(ang)
        d.line((64 + 18 * math.cos(a), 64 + 18 * math.sin(a), 64 + 40 * math.cos(a), 64 + 40 * math.sin(a)), fill=(190, 255, 245, 255), width=4)
    save(im, os.path.join(HUD, "icon_skill2.png"))
    # 背包
    im = canvas()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((34, 44, 94, 108), 12, fill=(92, 58, 36, 255))
    d.rounded_rectangle((42, 36, 86, 58), 8, fill=(140, 96, 58, 255))
    d.arc((46, 18, 82, 48), 200, 340, fill=(214, 186, 140, 255), width=7)
    d.line((64, 58, 64, 100), fill=(186, 150, 104, 255), width=4)
    save(im, os.path.join(HUD, "icon_bag.png"))
    # 碎片
    im = canvas()
    d = ImageDraw.Draw(im)
    d.polygon([(64, 16), (100, 48), (82, 108), (46, 108), (28, 48)], fill=(110, 220, 230, 255))
    d.polygon([(64, 16), (82, 48), (64, 100), (46, 48)], fill=(190, 255, 250, 180))
    save(im, os.path.join(HUD, "icon_shard.png"))
    # 暂停
    im = canvas()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((36, 28, 56, 100), 6, fill=cream)
    d.rounded_rectangle((72, 28, 92, 100), 6, fill=cream)
    save(im, os.path.join(HUD, "icon_pause.png"))
    # 消耗品：红瓶
    im = canvas()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((56, 22, 72, 40), 3, fill=(90, 70, 60, 255))
    d.ellipse((40, 40, 88, 108), outline=(220, 200, 170, 255), width=4)
    d.pieslice((44, 64, 84, 104), 0, 180, fill=(176, 36, 42, 255))
    d.rectangle((44, 78, 84, 92), fill=(176, 36, 42, 255))
    save(im, os.path.join(HUD, "icon_potion.png"))


def main():
    os.makedirs(ACT, exist_ok=True)
    os.makedirs(HUD, exist_ok=True)
    hero = Image.open(os.path.join(ART, "hero_sheet_v1.jpg")).convert("RGB")
    mobs = Image.open(os.path.join(ART, "mossroot_basic3_v1.jpg")).convert("RGB")
    # 高俯视 3/4 那一格，当作局内占位
    save(drop_shadow(crop_box(hero, (948, 63, 1200, 322), 8)), os.path.join(ACT, "hero.png"))
    # 头像：正面头和围巾
    head = crop_box(hero, (90, 8, 270, 188), 4)
    side = max(head.size)
    plate = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    plate.paste(head, ((side - head.width) // 2, (side - head.height) // 2), head)
    save(circle_crop(plate, 256), os.path.join(HUD, "portrait.png"))
    # 上排站姿：野猪、孢子菇、石壳甲
    save(drop_shadow(crop_box(mobs, (46, 56, 383, 314), 8)), os.path.join(ACT, "boar.png"))
    save(drop_shadow(crop_box(mobs, (513, 57, 757, 309), 8)), os.path.join(ACT, "shroom.png"))
    save(drop_shadow(crop_box(mobs, (859, 34, 1240, 323), 8)), os.path.join(ACT, "beetle.png"))
    icons()


if __name__ == "__main__":
    main()
