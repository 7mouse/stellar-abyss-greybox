#!/usr/bin/env python3
"""把拆件 PNG + 枢轴 JSON 收成 Skeleton2D 清单（拆件规范 §11 / §12）。

素材按 v2.1 原图位置使用，枢轴以 *_pivots.json 为准，不再做程序位移。
清掉半透明杂边和孤立杂点，关节盖同色圆垫。
网格部件只做很小的权重弯曲（拉伸控制在 15% 以内）。
描边色用色板第一格。上层部件末端压在父部件上的关节暗线改成自身填色。

用法：
  python3 tools/rig/import_rig.py --src art_src/rigs
  godot --headless --path . --script res://tools/rig/build_scenes.gd

依赖：pillow、numpy、scipy。不要跑 tools/data/gen_data.py。
"""
from __future__ import annotations

import argparse
import json
import math
import os
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

ALPHA_CUT = 40
SPECK_MIN = 10
MESH_STRETCH_LIMIT = 0.15
PAD = 1

HERO_ORDER = {
    "s": [
        "arm_upper_l_s", "forearm_l_s", "thigh_l_s", "shin_l_s", "backpack_s",
        "hair_back_s", "scarf_s_mesh", "torso_s_mesh", "thigh_r_s", "shin_r_s",
        "head_s", "sword_s", "arm_upper_r_s", "forearm_r_s",
    ],
    "f": [
        "shin_r_f", "shin_l_f", "thigh_r_f", "thigh_l_f", "torso_f_mesh",
        "forearm_r_f", "arm_upper_l_f", "head_f", "scarf_f_mesh", "arm_upper_r_f",
        "sword_f", "forearm_l_f",
    ],
    "b": [
        "sword_b", "shin_r_b", "shin_l_b", "thigh_r_b", "thigh_l_b",
        "arm_upper_r_b", "forearm_r_b", "arm_upper_l_b", "forearm_l_b",
        "torso_b_mesh", "head_b", "backpack_b", "scarf_b_mesh",
    ],
}
BOAR_ORDER = [
    "leg_hind_l_s", "leg_front_l_s", "tail_s", "body_s_mesh", "leg_hind_r_s",
    "leg_front_r_s", "head_s", "ear_s", "sprout_s",
]

HERO_SPRITE = {
    "head": "head", "hair_back": "head",
    "arm_upper_r": "upper_r", "arm_upper_l": "upper_l",
    "forearm_r": "forearm_r", "forearm_l": "forearm_l",
    "thigh_r": "thigh_r", "thigh_l": "thigh_l",
    "shin_r": "shin_r", "shin_l": "shin_l",
    "sword": "sword", "backpack": "backpack",
}
HERO_MESH = {"torso": ["spine", "chest"], "scarf": ["scarf0", "scarf1", "scarf2"]}
BOAR_SPRITE = {
    "head": "head", "ear": "ear", "sprout": "sprout", "tail": "tail",
    "leg_hind_r": "hind_r", "leg_hind_l": "hind_l",
    "leg_front_r": "front_r", "leg_front_l": "front_l",
}
BOAR_MESH = {"body": ["spine", "chest"]}


def logical_name(filename: str) -> str:
    n = filename[:-5] if filename.endswith("_mesh") else filename
    if len(n) > 2 and n[-2] == "_" and n[-1] in "sfb":
        n = n[:-2]
    return n


def wave(n: int, amp: float, phase: float = 0.0) -> list[float]:
    return [round(amp * math.sin(2 * math.pi * i / n + phase), 2) for i in range(n + 1)]


def bob(n: int, amp: float) -> list[list[float]]:
    return [[0.0, round(-amp * (0.5 - 0.5 * math.cos(2 * math.pi * i / n)), 2)] for i in range(n + 1)]


def walk_bob(n: int, amp: float) -> list[list[float]]:
    # 一步两次起伏
    return [[0.0, round(-amp * (0.5 - 0.5 * math.cos(4 * math.pi * i / n)), 2)] for i in range(n + 1)]


def hero_anims(facing: str) -> list[dict]:
    idle_rot = {
        "spine": wave(8, 1.0),
        "chest": wave(8, 2.4, 0.5),
        "head": wave(8, 2.0, 0.9),
        "scarf1": wave(8, 3.5, 0.4),
        "scarf2": wave(8, 6.5, 0.7),
    }
    if facing == "s":
        idle_rot.update({
            "upper_r": wave(8, 2.2, 1.1),
            "upper_l": wave(8, 1.8, 2.2),
            "forearm_r": wave(8, 1.4, 1.4),
            "forearm_l": wave(8, 1.2, 2.4),
        })
    else:
        # 正/背面手臂往两侧微微张开，避免扫过身体
        sign_r, sign_l = 1.0, -1.0
        idle_rot.update({
            "upper_r": wave(8, 2.5 * sign_r, 0.2),
            "upper_l": wave(8, 2.5 * sign_l, 0.2),
            "forearm_r": wave(8, 1.5 * sign_r, 0.6),
            "forearm_l": wave(8, 1.5 * sign_l, 0.6),
        })
    anims = [{
        "name": "idle", "fps": 8, "frames": 8, "loop": True,
        "rot": idle_rot, "pos": {"Motion": bob(8, 1.6)},
    }]
    if facing != "s":
        return anims
    anims.append({
        "name": "move", "fps": 12, "frames": 6, "loop": True,
        "rot": {
            "thigh_r": [-22, -6, 14, 24, 10, -12, -22],
            "thigh_l": [24, 10, -12, -22, -6, 14, 24],
            "shin_r": [18, 8, 12, 30, 26, 20, 18],
            "shin_l": [30, 26, 20, 18, 8, 12, 30],
            "upper_r": [16, 5, -8, -16, -4, 10, 16],
            "upper_l": [-16, -4, 10, 16, 5, -8, -16],
            "forearm_r": [8, 3, 0, 6, 10, 8, 8],
            "forearm_l": [6, 10, 8, 8, 3, 0, 6],
            "spine": [-2, -1, 1, 2, 1, -1, -2],
            "chest": [-1, 0, 1, 1.5, 1, 0, -1],
            "head": [2, 1, -1, -2, -1, 1, 2],
            "scarf1": [3, 1, -2, -4, -2, 1, 3],
            "scarf2": [5, 2, -3, -6, -3, 2, 5],
        },
        "pos": {"Motion": walk_bob(6, 3.5)},
    })
    anims.append({
        "name": "attack_1", "fps": 12, "frames": 7, "loop": False,
        "rot": {
            "upper_r": [0, -18, -38, -46, 42, 16, 4, 0],
            "forearm_r": [0, -8, -20, -26, 28, 10, 3, 0],
            "sword": [0, -4, -8, -10, 18, 6, 2, 0],
            "spine": [0, -3, -6, -7, 6, 2, 1, 0],
            "chest": [0, -1, -2, -3, 2, 1, 0, 0],
            "head": [0, -2, -4, -5, 3, 1, 0, 0],
            "upper_l": [0, 6, 12, 14, -8, -3, 0, 0],
            "thigh_r": [0, 2, 4, 4, -2, 0, 0, 0],
            "thigh_l": [0, -2, -3, -3, 2, 0, 0, 0],
            "scarf2": [0, 2, 4, 5, -6, -2, -1, 0],
        },
        "pos": {"Motion": [[0, 0], [0, 1], [0, 2], [0, 2], [0, -2], [0, -1], [0, 0], [0, 0]]},
    })
    anims.append({
        "name": "hit", "fps": 12, "frames": 6, "loop": False,
        "rot": {
            "spine": [0, 10, 14, 8, 4, 1, 0],
            "chest": [0, 3, 4, 2, 1, 0, 0],
            "head": [0, 14, 18, 10, 4, 1, 0],
            "upper_r": [0, 20, 26, 12, 5, 1, 0],
            "upper_l": [0, -14, -18, -8, -3, -1, 0],
            "forearm_r": [0, 8, 12, 5, 2, 0, 0],
            "thigh_r": [0, 5, 7, 3, 1, 0, 0],
            "scarf2": [0, 6, 8, 4, 2, 0, 0],
        },
        "pos": {"Motion": [[0, 0], [-3, 1], [-4, 2], [-2, 1], [-1, 0], [0, 0], [0, 0]]},
    })
    return anims


def boar_anims() -> list[dict]:
    return [
        {
            "name": "idle", "fps": 8, "frames": 8, "loop": True,
            "rot": {
                "spine": wave(8, 1.0, 0.2),
                "chest": wave(8, 2.2, 0.6),
                "head": wave(8, 2.2, 1.0),
                "ear": wave(8, 4.0, 1.4),
                "sprout": wave(8, 5.0, 0.3),
                "tail": wave(8, 7.0, 2.1),
            },
            "pos": {"Motion": bob(8, 1.4)},
        },
        {
            "name": "move", "fps": 12, "frames": 6, "loop": True,
            "rot": {
                "hind_r": [-16, -2, 14, 16, 4, -10, -16],
                "front_l": [-16, -2, 14, 16, 4, -10, -16],
                "hind_l": [16, 4, -10, -16, -2, 14, 16],
                "front_r": [16, 4, -10, -16, -2, 14, 16],
                "spine": [-1.5, 0, 1.5, 1.5, 0, -1.5, -1.5],
                "chest": [-2.5, -0.5, 2, 2.5, 0.5, -2, -2.5],
                "head": [3, 1, -2, -3, -1, 2, 3],
                "sprout": [6, 2, -3, -6, -2, 4, 6],
                "tail": [7, 2, -4, -7, -2, 4, 7],
                "ear": [2, 1, -1, -2, -1, 1, 2],
            },
            "pos": {"Motion": walk_bob(6, 2.8)},
        },
    ]


def clean_rgba(im: Image.Image) -> np.ndarray:
    """去掉低 alpha 杂边，孤立杂点删掉，边缘颜色改回内部色。"""
    a = np.array(im.convert("RGBA"))
    rgb = a[..., :3].copy()
    al = a[..., 3].copy()
    soft = (al > 0) & (al < ALPHA_CUT)
    al[al < ALPHA_CUT] = 0
    solid = al >= 180
    if solid.any() and ((al > 0) & ~solid).any():
        _, (iy, ix) = nd.distance_transform_edt(~solid, return_indices=True)
        edge = (al > 0) & ~solid
        rgb[edge] = rgb[iy[edge], ix[edge]]
    labeled, n = nd.label(al > 0)
    if n:
        counts = np.bincount(labeled.ravel())
        drop = np.where(counts < SPECK_MIN)[0]
        drop = drop[drop != 0]
        if drop.size:
            al[np.isin(labeled, drop)] = 0
    # 只把原来的半透明杂边补成实色，不往空白外扩
    solid = al >= ALPHA_CUT
    if solid.any() and soft.any():
        _, (iy, ix) = nd.distance_transform_edt(~solid, return_indices=True)
        fill = soft & ~solid
        # 只填紧挨着实色的一圈
        near = nd.binary_dilation(solid, iterations=1) & fill
        rgb[near] = rgb[iy[near], ix[near]]
        al[near] = 255
    return np.dstack([rgb, al])


def shift_arr(a: np.ndarray, dx: float, dy: float) -> np.ndarray:
    out = np.zeros_like(a)
    dx_i, dy_i = int(round(dx)), int(round(dy))
    h, w = a.shape[:2]
    ys = slice(max(0, dy_i), min(h, h + dy_i))
    xs = slice(max(0, dx_i), min(w, w + dx_i))
    ys2 = slice(max(0, -dy_i), min(h, h - dy_i))
    xs2 = slice(max(0, -dx_i), min(w, w - dx_i))
    out[ys, xs] = a[ys2, xs2]
    return out


def covers(mask: np.ndarray, x: float, y: float, margin: int = 1) -> bool:
    h, w = mask.shape
    xi, yi = int(round(x)), int(round(y))
    r2 = margin * margin + 0.1
    for dy in range(-margin, margin + 1):
        for dx in range(-margin, margin + 1):
            if dx * dx + dy * dy > r2:
                continue
            yy, xx = yi + dy, xi + dx
            if 0 <= yy < h and 0 <= xx < w and mask[yy, xx]:
                return True
    return False


def centroid(mask: np.ndarray) -> np.ndarray:
    ys, xs = np.where(mask)
    if xs.size == 0:
        return np.zeros(2)
    return np.array([xs.mean(), ys.mean()])


def closest_dir(child: np.ndarray, parent: np.ndarray) -> np.ndarray:
    if not child.any() or not parent.any():
        return np.zeros(2)
    dist = nd.distance_transform_edt(~parent)
    flat = np.where(child, dist, np.inf)
    idx = int(np.argmin(flat))
    cy, cx = np.unravel_index(idx, dist.shape)
    _, (iy, ix) = nd.distance_transform_edt(~parent, return_indices=True)
    direction = np.array([float(ix[cy, cx] - cx), float(iy[cy, cx] - cy)])
    if np.linalg.norm(direction) < 0.5:
        direction = centroid(parent) - centroid(child)
    nrm = np.linalg.norm(direction)
    if nrm < 1e-3:
        return np.zeros(2)
    return direction / nrm


def overlap_deficit(child: np.ndarray, parent: np.ndarray, overlap: int) -> float:
    er = parent
    for _ in range(overlap):
        er = nd.binary_erosion(er)
        if not er.any():
            return 0.0
    if not child.any():
        return 0.0
    dist = nd.distance_transform_edt(~er)
    return float(dist[child].min())


def cover_score(masks, pivots, shifts, cover) -> int:
    score = 0
    for part, keys in cover.items():
        for k in keys:
            if k not in pivots:
                continue
            s = shifts[part]
            if covers(masks[part], pivots[k][0] - s[0], pivots[k][1] - s[1]):
                score += 1
    return score


def seat_parts(masks, pivots, seats) -> dict[str, np.ndarray]:
    shifts = defaultdict(lambda: np.zeros(2))
    for seat in seats:
        if seat.get("collar"):
            part = seat["collar"]
            if part not in masks:
                continue
            neck = pivots[seat["pivot"]]
            root = pivots.get(seat.get("root_pivot", "scarf_root"), neck)
            ys, xs = np.where(masks[part])
            if xs.size == 0:
                continue
            band = ys <= ys.min() + 18
            if band.sum() < 10:
                continue
            dx = float(neck[0] - xs[band].mean())
            dx = float(np.clip(dx, -20, 20))
            best = np.zeros(2)
            for k in np.linspace(1, 0, 21):
                s = np.array([dx * k, 0.0])
                if covers(masks[part], neck[0] - s[0], neck[1] - s[1], 0) and covers(
                    masks[part], root[0] - s[0], root[1] - s[1], 0
                ):
                    best = s
                    break
            shifts[part] = shifts[part] + best
            print(f"  围巾回正 {part} dx={best[0]:.1f}")
            continue
        movers = [m for m in seat["movers"] if m in masks]
        target = seat["target"]
        if not movers or target not in masks:
            continue
        # 多个部件一起动：用它们的并集算缝
        union = np.zeros_like(next(iter(masks.values())))
        for m in movers:
            # 已经有的位移先反映到并集上
            union |= shift_arr(masks[m].astype(np.uint8), shifts[m][0], shifts[m][1]) > 0
        target_mask = shift_arr(masks[target].astype(np.uint8), shifts[target][0], shifts[target][1]) > 0
        deficit = overlap_deficit(union, target_mask, seat["overlap"])
        if deficit < 0.6:
            continue
        direction = closest_dir(union, target_mask)
        if np.linalg.norm(direction) < 1e-3:
            continue
        cover = seat["cover"]
        base_score = cover_score(masks, pivots, shifts, cover)
        best = None
        cap = min(deficit, seat["max_shift"])
        for dist in np.linspace(cap, 0, 18):
            delta = direction * float(dist)
            trial = defaultdict(lambda: np.zeros(2), {k: v.copy() for k, v in shifts.items()})
            for m in movers:
                trial[m] = trial[m] + delta
            if cover_score(masks, pivots, trial, cover) >= base_score:
                best = delta
                break
        if best is None or np.linalg.norm(best) < 0.5:
            continue
        for m in movers:
            shifts[m] = shifts[m] + best
        print(f"  贴合 {'+'.join(movers)} -> {target} ({best[0]:.1f},{best[1]:.1f})")
    return shifts


def hero_seats(_facing: str) -> list[dict]:
    # v2 原图已经把围巾、右臂和小臂接到位。
    return []


def boar_seats() -> list[dict]:
    # v2 原图已经把远侧前腿接进肚子。
    return []


def palette_outline(src: str, rel: str) -> list[float]:
    doc = json.load(open(os.path.join(src, rel), encoding="utf-8"))
    rgb = doc["colors"][0]["rgb"]
    return [round(rgb[0] / 255.0, 4), round(rgb[1] / 255.0, 4), round(rgb[2] / 255.0, 4), 1.0]


def suppress_covered_outline(cleaned: dict, pivots: dict, joints: list, line_rgb: list[float]) -> None:
    """子部件在关节圆头上的描边，如果压住父部件，就改成自己的填色。"""
    line = np.array(line_rgb[:3], float)
    by_l = {logical_name(name): img for name, img in cleaned.items()}
    for joint, _bone, parent_l, child_l, _radius in joints:
        if joint not in pivots or child_l not in by_l or parent_l not in by_l:
            continue
        img = by_l[child_l]
        parent = by_l[parent_l][..., 3] > 40
        m = img[..., 3] > 140
        if not m.any():
            continue
        h, w = m.shape
        yy, xx = np.mgrid[:h, :w]
        x, y = pivots[joint]
        near = (xx - x) ** 2 + (yy - y) ** 2 <= 15.0 ** 2
        din = nd.distance_transform_edt(m)
        rgb = img[..., :3].astype(float)
        dist = np.linalg.norm(rgb - line, axis=2)
        lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
        dark = (dist <= 42.0) | (lum < 100.0)
        hit = m & near & parent & (din <= 2.6) & dark
        n = int(hit.sum())
        if not n:
            continue
        src = m & ~hit & (lum >= 90.0)
        if not src.any():
            continue
        _, (iy, ix) = nd.distance_transform_edt(~src, return_indices=True)
        img[hit, :3] = img[iy[hit], ix[hit], :3]
        print(f"  盖住的圆头线 {child_l}@{joint} {n}px")


def median_color(img: np.ndarray, x: float, y: float) -> list[float]:
    h, w = img.shape[:2]
    for rad in (6, 10, 16, 28):
        x0, y0 = max(0, int(x) - rad), max(0, int(y) - rad)
        x1, y1 = min(w, int(x) + rad + 1), min(h, int(y) + rad + 1)
        win = img[y0:y1, x0:x1]
        m = win[..., 3] > 180
        if m.sum() >= 8:
            pix = win[..., :3][m].astype(float)
            col = np.median(pix, axis=0) / 255.0
            return [round(float(c), 3) for c in col]
    return [0.4, 0.28, 0.2]


def outline_color(images: list[np.ndarray]) -> list[float]:
    samples = []
    for img in images:
        m = img[..., 3] > 200
        if m.sum() < 40:
            continue
        pix = img[..., :3][m].astype(float)
        lum = pix @ np.array([0.2126, 0.7152, 0.0722])
        dark = pix[lum <= np.percentile(lum, 14)]
        if dark.size:
            samples.append(np.median(dark, axis=0))
    if not samples:
        return [0.15, 0.1, 0.08, 1.0]
    c = np.median(np.stack(samples), axis=0) * 0.55
    c = np.clip(c / 255.0, 0, 1)
    return [round(float(v), 3) for v in c] + [1.0]


def _chain_t(p: np.ndarray, origins: list[np.ndarray]) -> float:
    if len(origins) < 2:
        return 0.0
    total = 0.0
    segs = []
    for a, b in zip(origins, origins[1:]):
        ln = max(float(np.linalg.norm(b - a)), 1e-3)
        segs.append((a, b, ln))
        total += ln
    best_t, best_d, acc = 0.0, 1e9, 0.0
    for a, b, ln in segs:
        ab = b - a
        t = float(np.clip(np.dot(p - a, ab) / (ln * ln), 0.0, 1.0))
        d = float(np.linalg.norm(p - (a + ab * t)))
        if d < best_d:
            best_d = d
            best_t = (acc + t * ln) / total
        acc += ln
    return best_t


def _weights_from_t(t: float, n_bones: int) -> list[float]:
    w = [0.0, 0.0, 0.0, 0.0]
    if n_bones <= 1:
        w[0] = 1.0
        return w
    if n_bones == 2:
        w[0], w[1] = 1.0 - t, t
        return w
    # 三段线性：根 -> 中 -> 尖，相邻骨骼分享权重，梯度平，避免一格跳变。
    if t < 0.5:
        local = t / 0.5
        w[0], w[1] = 1.0 - local, local
    else:
        local = (t - 0.5) / 0.5
        w[1], w[2] = 1.0 - local, local
    return w


def grid_mesh(mask, crop, nudge, root, bone_world, bone_names):
    ys, xs = np.where(mask)
    if xs.size < 10:
        return None
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())
    cols, rows = 5, 6
    origins = [np.array(bone_world[n], float) for n in bone_names]
    canvas = []
    ts = np.zeros((rows, cols))
    opaque = np.zeros((rows, cols), dtype=bool)
    h, w = mask.shape
    for r in range(rows):
        for c in range(cols):
            cx = x0 + (x1 - x0) * c / (cols - 1)
            cy = y0 + (y1 - y0) * r / (rows - 1)
            canvas.append((cx, cy))
            p = np.array([cx + nudge[0] - root[0], cy + nudge[1] - root[1]])
            ts[r, c] = _chain_t(p, origins)
            xi, yi = int(round(cx)), int(round(cy))
            opaque[r, c] = 0 <= yi < h and 0 <= xi < w and mask[yi, xi]
    for _ in range(3):
        nxt = ts.copy()
        for r in range(rows):
            for c in range(cols):
                acc, n = ts[r, c], 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    rr, cc = r + dy, c + dx
                    if 0 <= rr < rows and 0 <= cc < cols:
                        acc += ts[rr, cc]
                        n += 1
                nxt[r, c] = acc / n
        ts = nxt
    points, uvs, weights, names = [], [], [], []
    for r in range(rows):
        for c in range(cols):
            cx, cy = canvas[r * cols + c]
            points.append([
                round(cx + nudge[0] - root[0], 2),
                round(cy + nudge[1] - root[1], 2),
            ])
            uvs.append([round(cx - crop[0], 2), round(cy - crop[1], 2)])
            ww = _weights_from_t(float(ts[r, c]), len(bone_names))
            for i in range(4):
                names.append(bone_names[i] if i < len(bone_names) else bone_names[-1])
                weights.append(round(ww[i], 3))
    tris = []
    for r in range(rows - 1):
        for c in range(cols - 1):
            i = r * cols + c
            tris.append([i, i + 1, i + cols])
            tris.append([i + 1, i + cols + 1, i + cols])
    stretch = _stretch(points, weights, names, bone_names, origins, opaque.reshape(-1), cols)
    return {
        "points": points, "uvs": uvs, "tris": tris,
        "bone_names": names, "weights": weights, "stretch": stretch,
    }


def _rot(p, origin, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    d = np.array(p) - origin
    return origin + np.array([d[0] * c - d[1] * s, d[0] * s + d[1] * c])


def _stretch(points, weights, names, bone_names, origins, opaque, cols) -> float:
    """尖端骨骼转 8° 时，不透明顶点之间距离变化的最大值。"""
    tip = bone_names[-1]
    posed = []
    for i, p in enumerate(points):
        acc = np.zeros(2)
        for k in range(4):
            w = weights[i * 4 + k]
            if w <= 0:
                continue
            bname = names[i * 4 + k]
            bi = bone_names.index(bname)
            src = np.array(p, float)
            if bname == tip:
                src = _rot(src, origins[bi], 8.0)
            acc += w * src
        posed.append(acc)
    worst = 0.0
    for i in range(len(points)):
        if not opaque[i]:
            continue
        for j in (i + 1, i + cols):
            if j >= len(points) or not opaque[j]:
                continue
            if j == i + 1 and (i + 1) % cols == 0:
                continue
            d0 = float(np.linalg.norm(np.array(points[i]) - np.array(points[j])))
            d1 = float(np.linalg.norm(posed[i] - posed[j]))
            if d0 > 2:
                worst = max(worst, abs(d1 - d0) / d0)
    return worst


def _closest_pair(child: np.ndarray, parent: np.ndarray):
    dist = nd.distance_transform_edt(~parent)
    idx = int(np.argmin(np.where(child, dist, np.inf)))
    cy, cx = np.unravel_index(idx, dist.shape)
    _, (iy, ix) = nd.distance_transform_edt(~parent, return_indices=True)
    return (int(cx), int(cy)), (int(ix[cy, cx]), int(iy[cy, cx])), float(dist[cy, cx])


def _paint_disk(img: np.ndarray, x: float, y: float, rad: float, color: np.ndarray) -> None:
    h, w = img.shape[:2]
    r = int(math.ceil(rad))
    xi, yi = int(round(x)), int(round(y))
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy > rad * rad:
                continue
            yy, xx = yi + dy, xi + dx
            if 0 <= yy < h and 0 <= xx < w and img[yy, xx, 3] < 240:
                img[yy, xx, :3] = color
                img[yy, xx, 3] = 255


def bridge_gaps(cleaned: dict, seats: list) -> None:
    """关节还悬着时，沿缝把子部件边缘色外扩几像素，不挪蹄子/手腕枢轴。"""
    by_l = {logical_name(n): im for n, im in cleaned.items()}
    for seat in seats:
        movers = seat.get("movers")
        parent_name = seat.get("target")
        if not movers or parent_name not in by_l:
            continue
        parent = by_l[parent_name]
        pm = parent[..., 3] > ALPHA_CUT
        for child_name in movers:
            if child_name not in by_l or child_name == parent_name:
                continue
            child = by_l[child_name]
            cm = child[..., 3] > ALPHA_CUT
            if not cm.any() or not pm.any():
                continue
            a, b, gap = _closest_pair(cm, pm)
            if gap < 1.5 or gap > 10:
                continue
            color = child[a[1], a[0], :3].copy()
            steps = max(1, int(gap))
            for s in range(1, steps + 1):
                t = s / (steps + 1)
                x = a[0] + (b[0] - a[0]) * t
                y = a[1] + (b[1] - a[1]) * t
                _paint_disk(child, x, y, 3.5, color)
            print(f"  外扩 {child_name} -> {parent_name} {gap:.1f}px")


def crop_box(img: np.ndarray):
    m = img[..., 3] > 0
    ys, xs = np.where(m)
    if xs.size == 0:
        return None
    h, w = img.shape[:2]
    x0 = max(0, int(xs.min()) - PAD)
    y0 = max(0, int(ys.min()) - PAD)
    x1 = min(w - 1, int(xs.max()) + PAD)
    y1 = min(h - 1, int(ys.max()) + PAD)
    return x0, y0, x1, y1


def r2(v) -> list[float]:
    return [round(float(v[0]), 2), round(float(v[1]), 2)]


def build_humanoid(piv, root, part_world, facing: str):
    def P(key):
        return np.array(piv[key], float) - root

    hip = (P("hip_l") + P("hip_r")) / 2
    chest = (P("shoulder_l") + P("shoulder_r")) / 2
    bones_w = {
        "root": np.zeros(2),
        "spine": hip,
        "chest": chest,
        "head": P("neck"),
        "upper_r": P("shoulder_r"),
        "forearm_r": P("elbow_r"),
        "upper_l": P("shoulder_l"),
        "forearm_l": P("elbow_l"),
        "thigh_r": P("hip_r"),
        "shin_r": P("knee_r"),
        "thigh_l": P("hip_l"),
        "shin_l": P("knee_l"),
    }
    hand = "r" if facing == "s" else "l"
    bones_w["sword"] = P("sword_grip")
    # 围巾链条跟着（可能被挪过的）围巾像素走，根仍钉在枢轴上
    scarf = part_world["scarf"]
    ys, xs = np.where(scarf["mask_placed"])
    if xs.size:
        w = np.clip(ys - np.percentile(ys, 45), 0, None) + 1.0
        hang = np.array([np.average(xs, weights=w), np.average(ys, weights=w)]) - root
    else:
        hang = P("scarf_root") + np.array([-20.0, 20.0])
    s0 = P("scarf_root")
    bones_w["scarf0"] = s0
    bones_w["scarf1"] = s0 + (hang - s0) * 0.48
    bones_w["scarf2"] = s0 + (hang - s0) * 0.92
    if "backpack_anchor" in piv:
        bones_w["backpack"] = P("backpack_anchor")
    parents = {
        "root": "", "spine": "root", "chest": "spine", "head": "chest",
        "upper_r": "chest", "forearm_r": "upper_r",
        "upper_l": "chest", "forearm_l": "upper_l",
        "thigh_r": "root", "shin_r": "thigh_r",
        "thigh_l": "root", "shin_l": "thigh_l",
        "sword": f"forearm_{hand}",
        "scarf0": "chest", "scarf1": "scarf0", "scarf2": "scarf1",
    }
    if "backpack" in bones_w:
        parents["backpack"] = "chest"
    order = [
        "root", "spine", "chest", "head",
        "upper_r", "forearm_r", "upper_l", "forearm_l", "sword",
        "thigh_r", "shin_r", "thigh_l", "shin_l",
        "scarf0", "scarf1", "scarf2",
    ]
    if "backpack" in bones_w:
        order.append("backpack")
    return bones_w, parents, order


def build_boar(piv, root, part_world):
    def P(key):
        return np.array(piv[key], float) - root

    hip = (P("hip_l") + P("hip_r")) / 2
    chest = (P("shoulder_l") + P("shoulder_r")) / 2
    bones_w = {
        "root": np.zeros(2),
        "spine": hip,
        "chest": chest,
        "head": P("neck"),
        "ear": P("ear_root"),
        "sprout": P("sprout_root"),
        "tail": P("tail_root"),
        "hind_r": P("hip_r"),
        "hind_l": P("hip_l"),
        "front_r": P("shoulder_r"),
        "front_l": P("shoulder_l"),
    }
    parents = {
        "root": "", "spine": "root", "chest": "spine", "head": "chest",
        "ear": "head", "sprout": "chest", "tail": "spine",
        "hind_r": "root", "hind_l": "root", "front_r": "root", "front_l": "root",
    }
    order = [
        "root", "spine", "chest", "head", "ear", "sprout", "tail",
        "hind_r", "hind_l", "front_r", "front_l",
    ]
    return bones_w, parents, order


def joints_for(kind: str, facing: str):
    if kind == "hero":
        hand = "r" if facing == "s" else "l"
        rows = [
            ("neck", "head", "torso", "head", 8),
            ("shoulder_r", "upper_r", "torso", "arm_upper_r", 6),
            ("shoulder_l", "upper_l", "torso", "arm_upper_l", 6),
            ("elbow_r", "forearm_r", "arm_upper_r", "forearm_r", 5),
            ("elbow_l", "forearm_l", "arm_upper_l", "forearm_l", 5),
            ("hip_r", "thigh_r", "torso", "thigh_r", 7),
            ("hip_l", "thigh_l", "torso", "thigh_l", 7),
            ("knee_r", "shin_r", "thigh_r", "shin_r", 6),
            ("knee_l", "shin_l", "thigh_l", "shin_l", 6),
            ("sword_grip", "sword", f"forearm_{hand}", "sword", 5),
            ("scarf_root", "scarf0", "torso", "scarf", 6),
        ]
        return rows
    return [
        ("neck", "head", "body", "head", 7),
        ("hip_r", "hind_r", "body", "leg_hind_r", 6),
        ("hip_l", "hind_l", "body", "leg_hind_l", 6),
        ("shoulder_r", "front_r", "body", "leg_front_r", 6),
        ("shoulder_l", "front_l", "body", "leg_front_l", 6),
        ("tail_root", "tail", "body", "tail", 5),
        ("ear_root", "ear", "head", "ear", 4),
        ("sprout_root", "sprout", "body", "sprout", 4),
    ]


def process_rig(spec, src, out_root, preview_dir):
    pivots_doc = json.load(open(os.path.join(src, spec["pivots"]), encoding="utf-8"))
    piv = {k: (float(v[0]), float(v[1])) for k, v in pivots_doc["pivots"].items()}
    root = np.array(piv["root"], float)
    parts_dir = os.path.join(src, spec["parts_dir"])
    order = spec["order"]
    cleaned = {}
    for name in order:
        fp = os.path.join(parts_dir, name + ".png")
        if not os.path.exists(fp):
            print("  缺部件", name)
            continue
        img = clean_rgba(Image.open(fp))
        if not (img[..., 3] > 0).any():
            print("  空部件", name)
            continue
        cleaned[name] = img
    line_rgb = [c * 255.0 for c in spec["outline"][:3]]
    suppress_covered_outline(cleaned, piv, joints_for(spec["kind"], spec["facing"]), line_rgb)
    part_world = {}
    for name, img in cleaned.items():
        part_world[logical_name(name)] = {
            "img": img, "shift": np.zeros(2), "mask_placed": img[..., 3] > ALPHA_CUT,
            "placed": img,
        }

    if spec["kind"] == "hero":
        bones_w, parents, bone_order = build_humanoid(piv, root, part_world, spec["facing"])
        sprite_map, mesh_map = HERO_SPRITE, HERO_MESH
    else:
        bones_w, parents, bone_order = build_boar(piv, root, part_world)
        sprite_map, mesh_map = BOAR_SPRITE, BOAR_MESH

    rel = os.path.join("assets/rigs", spec["asset_dir"])
    abs_dir = os.path.join(out_root, rel)
    os.makedirs(abs_dir, exist_ok=True)

    z_of = {name: i for i, name in enumerate(order)}
    sprites, meshes = [], []
    saved_imgs = []
    for name, img in cleaned.items():
        logical = logical_name(name)
        box = crop_box(img)
        if box is None:
            continue
        x0, y0, x1, y1 = box
        crop = img[y0:y1 + 1, x0:x1 + 1]
        tex_rel = f"{rel}/{name}.png".replace("\\", "/")
        Image.fromarray(crop).save(os.path.join(out_root, tex_rel))
        saved_imgs.append(img)
        nudge = np.zeros(2)
        cx = (x0 + x1) / 2
        cy = (y0 + y1) / 2
        char = np.array([cx - root[0], cy - root[1]])
        tex = "res://" + tex_rel
        if logical in mesh_map:
            bone_names = [b for b in mesh_map[logical] if b in bones_w]
            mesh = grid_mesh(
                img[..., 3] > ALPHA_CUT, (x0, y0), nudge, root, bones_w, bone_names,
            )
            if mesh is None:
                continue
            if mesh["stretch"] > MESH_STRETCH_LIMIT:
                print(f"  警告 {name} 8° 弯曲拉伸 {mesh['stretch']*100:.1f}% 超过 15%")
            else:
                print(f"  网格 {name} 8° 拉伸 {mesh['stretch']*100:.1f}%")
            meshes.append({
                "name": name, "tex": tex, "z": z_of[name],
                "points": mesh["points"], "uvs": mesh["uvs"], "tris": mesh["tris"],
                "bone_names": mesh["bone_names"], "weights": mesh["weights"],
            })
        elif logical in sprite_map:
            bone = sprite_map[logical]
            if bone not in bones_w:
                continue
            local = char - bones_w[bone]
            sprites.append({
                "name": name, "bone": bone, "tex": tex, "z": z_of[name], "pos": r2(local),
            })

    pads = []
    for joint, bone, parent_logical, child_logical, radius in joints_for(spec["kind"], spec["facing"]):
        if joint not in piv or bone not in bones_w:
            continue
        child = part_world.get(child_logical)
        parent = part_world.get(parent_logical)
        src_img = None
        if child is not None:
            src_img = child["placed"]
        elif parent is not None:
            src_img = parent["placed"]
        if src_img is None:
            continue
        col = median_color(src_img, piv[joint][0], piv[joint][1])
        zs = []
        for logical, table in ((parent_logical, None), (child_logical, None)):
            for fn, z in z_of.items():
                if logical_name(fn) == logical:
                    zs.append(z)
        z = min(zs) if zs else 0
        pads.append({
            "joint": joint, "bone": bone, "radius": radius, "color": col, "z": z,
        })

    bones = []
    for name in bone_order:
        parent = parents[name]
        local = bones_w[name] if parent == "" else bones_w[name] - bones_w[parent]
        bones.append({"name": name, "parent": parent, "pos": r2(local)})
    if len(bones) > 20:
        raise SystemExit(f"{spec['id']} 骨骼 {len(bones)} 超过 20")

    manifest = {
        "id": spec["id"],
        "scene": spec["scene"],
        "outline_color": spec["outline"],
        "outline_width": 1.5,
        "bones": bones,
        "sprites": sprites,
        "meshes": meshes,
        "pads": pads,
        "anims": spec["anims"](),
    }
    man_dir = os.path.join(out_root, "assets/rigs/manifests")
    os.makedirs(man_dir, exist_ok=True)
    with open(os.path.join(man_dir, spec["id"] + ".json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False)
    _debug_composite(spec["id"], cleaned, {n: np.zeros(2) for n in cleaned}, piv, pads, preview_dir)
    print(f"{spec['id']}: 部件 {len(sprites)} 网格 {len(meshes)} 骨骼 {len(bones)} 垫片 {len(pads)}")
    return manifest


def _debug_composite(rid, cleaned, shifts, piv, pads, preview_dir):
    canvas = np.zeros((256, 256, 4), np.uint8)
    # 按 z 画。cleaned 的插入顺序就是 order
    for name, img in cleaned.items():
        placed = shift_arr(img, shifts[name][0], shifts[name][1])
        a = placed[..., 3:4].astype(float) / 255.0
        canvas[..., :3] = (canvas[..., :3] * (1 - a) + placed[..., :3] * a).astype(np.uint8)
        canvas[..., 3] = np.maximum(canvas[..., 3], placed[..., 3])
    im = Image.fromarray(canvas)
    os.makedirs(preview_dir, exist_ok=True)
    im.save(os.path.join(preview_dir, f"{rid}.png"))


def write_pad(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    n = 32
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    dr.ellipse((1, 1, n - 2, n - 2), fill=(255, 255, 255, 255))
    im.save(path)


def specs_for(src: str) -> list[dict]:
    hero = "hero/hero_parts_{f}_v2_1_pivots.json"
    hero_line = palette_outline(src, "hero/hero_palette_src.json")
    boar_line = palette_outline(src, "sprout_boar/sprout_boar_palette_src.json")
    return [
        {
            "id": "hero_s", "kind": "hero", "facing": "s", "asset_dir": "hero/s",
            "scene": "res://scenes/rigs/hero_s.tscn",
            "pivots": hero.format(f="s"), "parts_dir": "hero/parts_v2_1",
            "order": HERO_ORDER["s"], "seats": lambda: hero_seats("s"),
            "anims": lambda: hero_anims("s"), "outline": hero_line,
        },
        {
            "id": "hero_f", "kind": "hero", "facing": "f", "asset_dir": "hero/f",
            "scene": "res://scenes/rigs/hero_f.tscn",
            "pivots": hero.format(f="f"), "parts_dir": "hero/parts_v2_1",
            "order": HERO_ORDER["f"], "seats": lambda: hero_seats("f"),
            "anims": lambda: hero_anims("f"), "outline": hero_line,
        },
        {
            "id": "hero_b", "kind": "hero", "facing": "b", "asset_dir": "hero/b",
            "scene": "res://scenes/rigs/hero_b.tscn",
            "pivots": hero.format(f="b"), "parts_dir": "hero/parts_v2_1",
            "order": HERO_ORDER["b"], "seats": lambda: hero_seats("b"),
            "anims": lambda: hero_anims("b"), "outline": hero_line,
        },
        {
            "id": "mushling_s", "kind": "boar", "facing": "s", "asset_dir": "mushling/s",
            "scene": "res://scenes/rigs/mushling_s.tscn",
            "pivots": "sprout_boar/sprout_boar_parts_s_v2_1_pivots.json",
            "parts_dir": "sprout_boar/parts_v2_1", "order": BOAR_ORDER,
            "seats": boar_seats, "anims": boar_anims, "outline": boar_line,
        },
    ]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="art_src/rigs")
    ap.add_argument("--out", default=".")
    args = ap.parse_args()
    if not os.path.isdir(args.src):
        raise SystemExit(f"找不到拆件目录 {args.src}")
    write_pad(os.path.join(args.out, "assets/rigs/joint_pad.png"))
    preview = "/tmp/riganal"
    for spec in specs_for(args.src):
        print("==", spec["id"])
        process_rig(spec, args.src, args.out, preview)


if __name__ == "__main__":
    main()
