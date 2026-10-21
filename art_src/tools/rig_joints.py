#!/usr/bin/env python3
"""rig_joints: joint post-processing shared by cut_partsheet.py and rig_patch.py (rig-parts-spec §4/§11).

All functions work on float RGBA arrays (H,W,4) in 0..1, full-canvas layers, at SOURCE (2x) resolution.
Points are (x,y). Overlap sizes in configs are given at 1:1 and multiplied by `scale` (2 for 2x sources).

Main features
- round_cap(): extend a part's joint end along the bone direction with a round (half-disc) head,
  colour-filled by extruding the part's own edge colours, and re-outlined so the line never breaks.
- line_color(): the part/character outline colour sampled from real line pixels (darkest boundary band).
- palette(): k-means source palette (8-16 colours) that always contains the outline + highlight colour.
- joint_gap_test(): rotate the child +-angle around the pivot and count uncovered pixels near the joint.
"""
import numpy as np
from PIL import Image
from scipy import ndimage as nd
from scipy.cluster.vq import kmeans2

SMALL = (4, 8)    # forearm, shin, hand, ear, tail, sprout (1:1 px)
BIG = (10, 20)    # body, thigh/upper-arm root, head

# ---------------------------------------------------------------- io helpers
def to_f(img):
    return np.asarray(img.convert('RGBA'), dtype=np.float32) / 255.0

def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')

def grid(shape):
    H, W = shape[:2]
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    return xs + 0.5, ys + 0.5

def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114

# ---------------------------------------------------------------- colour
def boundary_band(alpha, width):
    m = alpha > 0.5
    din = nd.distance_transform_edt(m)
    return m & (din <= width) & (alpha > 0.8)

def line_color(layers, width=2.5, dark_frac=0.25):
    """Outline colour from real line pixels: darkest `dark_frac` of the boundary band of every part."""
    px = []
    for a in layers:
        if a is None:
            continue
        b = boundary_band(a[..., 3], width)
        if b.sum():
            px.append(a[..., :3][b])
    px = np.concatenate(px)
    L = lum(px)
    sel = px[L <= np.quantile(L, dark_frac)]
    return np.median(sel, axis=0)

def defringe(a, width=1.6, thresh=0.12):
    """Replace light halo pixels on the silhouette edge (white matte leftovers) by nearest interior colour."""
    al = a[..., 3]
    m = al > 0.5
    if not m.any():
        return a
    din = nd.distance_transform_edt(m)
    edge = (al > 0.02) & (din <= width)
    inner = m & (din > width + 1.5)
    if not inner.any():
        return a
    _, (iy, ix) = nd.distance_transform_edt(~inner, return_indices=True)
    ref = a[..., :3][iy, ix]
    bad = edge & (lum(a[..., :3]) > lum(ref) + thresh)
    out = a.copy()
    out[..., :3][bad] = ref[bad]
    return out

def fill_holes(a, max_area=None, iters=60, close_r=0, box=None):
    """Fill enclosed transparent holes (e.g. left by red-scarf erasing) with a smooth diffusion of the
    surrounding colours (normalised-convolution inpaint), so no blotchy nearest-neighbour patches."""
    m = a[..., 3] > 0.5
    filled = nd.binary_fill_holes(m)
    if close_r:
        yy, xx = np.mgrid[-close_r:close_r + 1, -close_r:close_r + 1]
        disk = xx * xx + yy * yy <= close_r * close_r
        filled = nd.binary_fill_holes(nd.binary_closing(np.pad(m, close_r + 1), disk)[close_r + 1:-close_r - 1, close_r + 1:-close_r - 1]) | filled
    hole = filled & ~m
    if box is not None:
        bm = np.zeros_like(hole); bm[box[1]:box[3], box[0]:box[2]] = True
        hole &= bm
    if max_area is not None:
        lab, n = nd.label(hole)
        for i in range(1, n + 1):
            if (lab == i).sum() > max_area:
                hole[lab == i] = False
    if not hole.any():
        return a, 0
    known = (m & (a[..., 3] > 0.9)).astype(np.float32)
    col = a[..., :3] * known[..., None]
    w = known.copy()
    for _ in range(iters):
        col2 = np.stack([nd.uniform_filter(col[..., c], 5) for c in range(3)], -1)
        w2 = nd.uniform_filter(w, 5)
        est = col2 / np.maximum(w2, 1e-4)[..., None]
        upd = hole & (w2 > 1e-3)
        col[upd] = est[upd] * 1.0
        w[upd] = 1.0
        col[known > 0] = a[..., :3][known > 0]
    out = a.copy()
    out[..., :3][hole] = col[hole]
    out[..., 3][hole] = 1.0
    return out, int(hole.sum())

# ---------------------------------------------------------------- geometry
def centroid(alpha):
    ys, xs = np.nonzero(alpha > 0.5)
    return np.array([xs.mean() + 0.5, ys.mean() + 0.5])

def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 1e-6 else np.array([0.0, -1.0])

def end_profile(alpha, p, u, band=6.0):
    """Measure the part end that points along u past pivot p.
    returns dict: t_end (furthest projection along u on the centre strip), s0 (centre-line offset), hw (half width)."""
    X, Y = grid(alpha.shape)
    m = alpha > 0.5
    v = np.array([-u[1], u[0]])
    t = (X - p[0]) * u[0] + (Y - p[1]) * u[1]
    s = (X - p[0]) * v[0] + (Y - p[1]) * v[1]
    tm, sm = t[m], s[m]
    if tm.size == 0:
        return None
    tmax = tm.max()
    tref = min(tmax, 0.0) - 2.0
    sel = (tm > tref - band * 2) & (tm <= tref)
    if sel.sum() < 4:
        sel = tm > tmax - band * 2
    lo, hi = np.quantile(sm[sel], [0.04, 0.96])
    s0, hw = (lo + hi) / 2, max((hi - lo) / 2, 1.0)
    strip = np.abs(sm - s0) <= max(hw * 0.45, 1.0)
    t_end = tm[strip].max() if strip.any() else tmax
    return dict(t_end=float(t_end), s0=float(s0), hw=float(hw), tref=float(tref), v=v)

def capsule_sdf(X, Y, a, b, r):
    ax, ay = a; bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    h = np.clip(((X - ax) * dx + (Y - ay) * dy) / max(L2, 1e-6), 0, 1)
    return np.hypot(X - ax - h * dx, Y - ay - h * dy) - r

# ---------------------------------------------------------------- the round cap
def _end_halfwidth(m, t, s, t_at, s0, band):
    sel = m & (t > t_at - band) & (t <= t_at + 0.5)
    if sel.sum() < 3:
        return None
    ss = s[sel]
    return max(abs(ss.min() - s0), abs(ss.max() - s0)) + 0.5

def round_cap(a, p, u, ovl_range, scale=2, on_top=False, line_rgb=None, line_w=None,
              target=None, shade=0.10, cap_r=None, hide_under=None):
    """Give part `a` a round overlapping head at pivot p, pointing along unit vector u.
    ovl_range: (min,max) overlap past the pivot at 1:1. Parts drawn on top use the low end of the
    range +1px (they are visible), parts underneath near the top of the range (hidden). `target` forces a value.
    Shape: half-ellipse whose lateral radius = the part's own end width (so the flat cut corners are
    absorbed, no notches) and whose tip lies exactly `target` px past the pivot; a straight bridge
    fills any gap between the old end and the head. Nothing of the original part is removed.
    Returns (new_rgba, info)."""
    u = unit(u)
    lo, hi = ovl_range[0] * scale, ovl_range[1] * scale
    prof = end_profile(a[..., 3], p, u)
    if prof is None:
        return a, dict(skipped='empty')
    t_end, s0, hw, v = prof['t_end'], prof['s0'], prof['hw'], prof['v']
    info = dict(before=round(t_end / scale, 1), half_width=round(hw / scale, 1))
    if t_end > hi + 1:
        info.update(after=info['before'], action='kept (already deeper than range)')
        return a, info
    if target is not None:
        want = target * scale
        hi = max(hi, want)
    else:
        # +1px@1:1 margin so the value survives anti-aliasing / downscale
        want = lo + scale if on_top else hi - 0.5 * scale   # hidden parts: near the top of the range
    if t_end >= want:
        want = t_end
    want = float(np.clip(want, lo, hi))
    X, Y = grid(a.shape)
    P = np.asarray(p, dtype=np.float64)
    t = (X - P[0]) * u[0] + (Y - P[1]) * u[1]
    s = (X - P[0]) * v[0] + (Y - P[1]) * v[1]
    old = a[..., 3]
    m_old = old > 0.5
    tc = min(t_end - 0.5 * scale, want - 2 * scale)          # ellipse centre (just inside the old end)
    b = _end_halfwidth(m_old, t, s, min(tc, t_end), s0, 2.5 * scale) or hw
    b = min(b, hw * 1.15)
    if cap_r is not None:
        b = min(b, cap_r * scale)
    ax_ = max(want - tc, 1.0)
    # ellipse (only the half beyond tc) + bridge rectangle from deep inside the part to tc
    q = np.sqrt(((t - tc) / ax_) ** 2 + ((s - s0) / b) ** 2)
    sdf_e = (q - 1) * min(ax_, b)
    sdf_e = np.where(t >= tc, sdf_e, np.inf)
    t_in = min(prof['tref'], tc) - 3 * scale
    sdf_r = np.maximum(np.abs(s - s0) - b, np.maximum(t_in - t, t - tc))
    sdf = np.minimum(sdf_e, sdf_r)
    cov = np.clip(0.5 - sdf, 0, 1).astype(np.float32)
    if hide_under is not None:
        # only grow where an upper layer already covers -> invisible in the rest pose, fills gaps when rotating
        cov = np.minimum(cov, nd.grey_erosion(hide_under, size=(3, 3)))
    # restrict the bridge to the gap region: only where the old part is absent near the end
    new_a = np.maximum(old, cov)
    added = new_a > old + 0.05
    out = a.copy()
    lw = line_w if line_w is not None else 1.0 * scale
    src = m_old & (nd.distance_transform_edt(m_old) > lw + 1.5) & (old > 0.9)
    if not src.any():
        src = m_old
    _, (iy, ix) = nd.distance_transform_edt(~src, return_indices=True)
    fillc = a[..., :3][iy, ix]
    rad = np.clip(np.abs(s - s0) / max(b, 1), 0, 1)
    fillc = fillc * (1 - shade * rad[..., None] ** 2)
    w = (np.clip((new_a - old) / np.maximum(new_a, 1e-3), 0, 1) * added)[..., None]
    out[..., :3] = out[..., :3] * (1 - w) + fillc * w
    out[..., 3] = new_a
    if line_rgb is not None:
        m_new = new_a > 0.5
        din = nd.distance_transform_edt(m_new)
        near = nd.distance_transform_edt(~added) <= lw + 2.5
        st = (np.clip(lw + 0.5 - din, 0, 1) * near * (new_a > 0.02))[..., None] * 0.92
        out[..., :3] = out[..., :3] * (1 - st) + np.asarray(line_rgb)[None, None, :] * st
    prof2 = end_profile(out[..., 3], p, u)
    info.update(after=round(prof2['t_end'] / scale, 1), action='round cap', target=round(want / scale, 1),
                cap_half_width=round(b / scale, 1), added_px_1to1=int(added.sum() / scale / scale))
    return out, info

# ---------------------------------------------------------------- transforms
def translate(a, d):
    img = to_img(a)
    W, H = img.size
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    out.alpha_composite(img, (int(round(d[0])), int(round(d[1]))))
    return to_f(out)

def rotate_about(a, p, deg):
    """Rotate counter-clockwise (screen) by deg around p using premultiplied bicubic."""
    pm = a.copy(); pm[..., :3] *= pm[..., 3:4]
    chans = []
    for c in range(4):
        im = Image.fromarray(pm[..., c].astype(np.float32), 'F')
        chans.append(np.asarray(im.rotate(deg, resample=Image.BICUBIC, center=tuple(p))))
    r = np.stack(chans, -1)
    al = np.clip(r[..., 3], 0, 1)
    r[..., :3] = np.where(al[..., None] > 1e-4, r[..., :3] / np.maximum(al[..., None], 1e-4), 0)
    r[..., 3] = al
    return np.clip(r, 0, 1)

# ---------------------------------------------------------------- self-check
def joint_gap_test(parent, child, p, angles=(-30, -15, 0, 15, 30), frac=0.6, scale=2, u_child=None):
    """Count uncovered pixels (at 1:1) inside a disc around the pivot while the child rotates.
    disc radius = frac * min(half width of parent, child) at the pivot."""
    def hw_at(al, uu):
        pr = end_profile(al, p, uu)
        return pr['hw'] if pr else 1.0
    uc = unit(u_child) if u_child is not None else unit(np.asarray(p) - centroid(child[..., 3]))
    rc = frac * min(hw_at(child[..., 3], uc), hw_at(parent[..., 3], -uc))
    X, Y = grid(parent.shape)
    disc = np.hypot(X - p[0], Y - p[1]) <= rc
    res = {}
    for ang in angles:
        c = rotate_about(child, p, ang) if ang else child
        cover = np.maximum(parent[..., 3], c[..., 3])
        res[ang] = round(float(((cover < 0.5) & disc).sum()) / (scale * scale), 1)
    return res, rc / scale

# ---------------------------------------------------------------- palette
def palette(layers, k=12, line_rgb=None, seed=7, chroma_w=2.5, dedup=0.10):
    """Source palette strip for the recolour shader: k-means on opaque pixels + outline + highlight.
    Clustering runs in an opponent space with chroma weighted x`chroma_w`, so small but distinct hues
    (red scarf, green sprout) get their own slots instead of being swallowed by the big brown/beige areas.
    returns list of (r,g,b) 0..255: outline first, then dark->light, highlight last; 8..16 colours."""
    px = np.concatenate([a[..., :3][a[..., 3] > 0.9] for a in layers if a is not None]).astype(np.float64)
    rng = np.random.default_rng(seed)
    if len(px) > 60000:
        px = px[rng.choice(len(px), 60000, replace=False)]
    L = lum(px)
    opp = np.stack([L, chroma_w * (px[:, 0] - px[:, 1]), chroma_w * ((px[:, 0] + px[:, 1]) / 2 - px[:, 2])], 1)
    _, lab = kmeans2(opp, k, minit='++', seed=seed)
    cols = []
    for i in range(k):
        m = lab == i
        if m.sum() > len(px) * 0.004:
            cols.append(np.median(px[m], axis=0))
    highlight = np.median(px[L >= np.quantile(L, 0.995)], axis=0)
    out = [np.asarray(line_rgb)] if line_rgb is not None else []
    cols.sort(key=lambda c: lum(c))
    for c in cols:
        if all(np.abs(c - o).sum() > dedup for o in out) and np.abs(c - highlight).sum() > dedup:
            out.append(c)
    out = out[:15] + [highlight]
    return [tuple(int(round(x * 255)) for x in c) for c in out]

def palette_png(cols, path, cell=16):
    im = Image.new('RGBA', (cell * len(cols), cell), (0, 0, 0, 0))
    for i, c in enumerate(cols):
        im.paste(Image.new('RGBA', (cell, cell), c + (255,)), (i * cell, 0))
    im.save(path)
