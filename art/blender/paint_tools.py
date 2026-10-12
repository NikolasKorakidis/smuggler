"""Procedural texture painting for generated aircraft (runs inside Blender, numpy only).

Rasterize meshes into their UV layout to get a world position + normal for every
texel, then paint with rules written in 3D (stripes, ribs, soot, chips...).
Outputs base colour (sRGB), ORM (R=1, G=roughness, B=metal) and a normal map.
"""
import bpy
import numpy as np

# --- rasterizing ---------------------------------------------------------------

def rasterize(items, W, H, eps=0.02):
    """items: [(object, part_id, material_names or None)]. Returns P, N, PART, MASK."""
    P = np.zeros((H, W, 3), np.float32)
    N = np.zeros((H, W, 3), np.float32)
    PART = np.zeros((H, W), np.int16)
    MASK = np.zeros((H, W), bool)
    for ob, part, mats in items:
        me = ob.data
        me.calc_loop_triangles()
        nt = len(me.loop_triangles)
        loops = np.empty(nt * 3, np.int32)
        me.loop_triangles.foreach_get("loops", loops)
        verts = np.empty(nt * 3, np.int32)
        me.loop_triangles.foreach_get("vertices", verts)
        tmat = np.empty(nt, np.int32)
        me.loop_triangles.foreach_get("material_index", tmat)
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        mw = np.array(ob.matrix_world, np.float32)
        co = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
        uv = np.empty(len(me.loops) * 2, np.float32)
        me.uv_layers.active.data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2) * np.array([W, H], np.float32)
        cn = np.empty(len(me.loops) * 3, np.float32)
        me.corner_normals.foreach_get("vector", cn)
        cn = cn.reshape(-1, 3) @ mw[:3, :3].T
        keep = None
        if mats:
            keep = {i for i, m in enumerate(me.materials) if m and m.name in mats}
        slot_part = None
        if isinstance(part, dict):
            slot_part = {i: part[m.name] for i, m in enumerate(me.materials) if m and m.name in part}
            keep = set(slot_part)
        loops, verts = loops.reshape(-1, 3), verts.reshape(-1, 3)
        for t in range(nt):
            if keep is not None and tmat[t] not in keep:
                continue
            q = uv[loops[t]]
            (x0, y0), (x1, y1), (x2, y2) = q
            den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(den) < 1e-9:
                continue
            xa, xb = int(max(np.floor(q[:, 0].min()), 0)), int(min(np.ceil(q[:, 0].max()), W - 1))
            ya, yb = int(max(np.floor(q[:, 1].min()), 0)), int(min(np.ceil(q[:, 1].max()), H - 1))
            if xb < xa or yb < ya:
                continue
            gx, gy = np.meshgrid(np.arange(xa, xb + 1) + 0.5, np.arange(ya, yb + 1) + 0.5)
            l0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
            l1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
            l2 = 1.0 - l0 - l1
            inside = (l0 >= -eps) & (l1 >= -eps) & (l2 >= -eps)
            if not inside.any():
                continue
            iy, ix = np.nonzero(inside)
            b = np.stack([l0[inside], l1[inside], l2[inside]], 1)
            p = co[verts[t]]
            n = cn[loops[t]]
            yy, xx = iy + ya, ix + xa
            P[yy, xx] = b @ p
            nn = b @ n
            N[yy, xx] = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-6)
            PART[yy, xx] = slot_part[tmat[t]] if slot_part is not None else part
            MASK[yy, xx] = True
    return P, N, PART, MASK


def dilate(mask, arrays, iters=6):
    """Grow the painted area outward so filtering never samples empty texels."""
    m = mask.copy()
    shifts = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    for _ in range(iters):
        grown = np.zeros_like(m)
        for dy, dx in shifts:
            sm = np.roll(m, (dy, dx), (0, 1))
            new = sm & ~m & ~grown
            if new.any():
                for a in arrays:
                    a[new] = np.roll(a, (dy, dx), (0, 1))[new]
                grown |= new
        m |= grown
    return m

# --- noise ---------------------------------------------------------------------

_PERM = np.random.RandomState(1979).permutation(256)
_PERM = np.concatenate([_PERM, _PERM]).astype(np.int64)


def _hash(ix, iy, iz):
    return _PERM[_PERM[_PERM[ix & 255] + (iy & 255)] + (iz & 255)]


def vnoise(p):
    """Smooth value noise in [0, 1] for points (n, 3)."""
    i = np.floor(p).astype(np.int64)
    f = (p - i).astype(np.float32)
    u = f * f * (3 - 2 * f)
    out = np.zeros(len(p), np.float32)
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                out += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz) / 255.0
    return out


def fbm(p, scale, octaves=4, seed=0):
    """Fractal noise in roughly [0, 1]. scale: frequency per metre, scalar or (3,)."""
    q = p * np.asarray(scale, np.float32) + np.float32(seed * 17.31)
    total, amp, norm = np.zeros(len(p), np.float32), 0.5, 0.0
    for _ in range(octaves):
        total += amp * vnoise(q)
        norm += amp
        q = q * 2.03 + 11.7
        amp *= 0.5
    return total / norm


def smoothstep(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = np.asarray(t, np.float32)
    if a.ndim == 2 and t.ndim == 1:
        t = t[:, None]
    return a + (b - a) * t

# --- output --------------------------------------------------------------------

def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.stack([-dx * strength, -dy * strength, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def write_image(img, rgb):
    H, W = rgb.shape[:2]
    if img.size[0] != W or img.size[1] != H:
        img.scale(W, H)
    px = np.ones((H, W, 4), np.float32)
    px[..., :3] = rgb
    img.pixels.foreach_set(px.ravel())
    img.update()


def save_image(img, path):
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def textured_material(name, W, H):
    """Principled material wired to base / ORM / normal images (glTF-friendly)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    for n in [n for n in nt.nodes if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL")]:
        nt.nodes.remove(n)
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    imgs = {}
    for key, cs in (("base", "sRGB"), ("orm", "Non-Color"), ("normal", "Non-Color")):
        iname = f"{name}_{key}"
        img = bpy.data.images.get(iname)
        if img and tuple(img.size) != (W, H):
            bpy.data.images.remove(img)
            img = None
        img = img or bpy.data.images.new(iname, W, H, alpha=False)
        img.colorspace_settings.name = cs
        imgs[key] = img
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = imgs["base"]
    nt.links.new(tb.outputs["Color"], bsdf.inputs["Base Color"])
    to = nt.nodes.new("ShaderNodeTexImage")
    to.image = imgs["orm"]
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = imgs["normal"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    m.use_backface_culling = True
    return m, imgs


def ambient_occlusion(items, W, H, bvh, rays=12, dist=0.25, down=4):
    """Soft contact shadows: fraction of short rays from each texel that escape. Computed on a
    grid `down` times coarser than the texture (ray casting from Python is slow), then upscaled."""
    import mathutils
    w, h = max(W // down, 8), max(H // down, 8)
    P, N, PART, MASK = rasterize(items, w, h)
    rng = np.random.RandomState(7)
    u, v = rng.rand(rays), rng.rand(rays)
    dirs = np.stack([np.sqrt(u) * np.cos(2 * np.pi * v), np.sqrt(u) * np.sin(2 * np.pi * v), np.sqrt(1 - u)], 1)
    ao = np.ones((h, w), np.float32)
    for y, x in zip(*np.nonzero(MASK)):
        n = mathutils.Vector(N[y, x])
        if n.length < 0.5:
            continue
        t = n.orthogonal().normalized()
        b = n.cross(t)
        o = mathutils.Vector(P[y, x]) + n * 0.002
        hit = 0
        for dx, dy, dz in dirs:
            if bvh.ray_cast(o, t * dx + b * dy + n * dz, dist)[0] is not None:
                hit += 1
        ao[y, x] = 1.0 - hit / rays
    dilate(MASK, [ao], iters=3)
    big = np.kron(ao, np.ones((down, down), np.float32))[:H, :W]
    if big.shape != (H, W):
        big = np.pad(big, ((0, H - big.shape[0]), (0, W - big.shape[1])), mode="edge")
    k = np.ones(down * 2 + 1, np.float32) / (down * 2 + 1)  # soften the upscale steps
    big = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, big)
    big = np.apply_along_axis(lambda c: np.convolve(c, k, mode="same"), 0, big)
    return big


def paint(items, W, H, rules, imgs, out_dir, normal_strength=6.0, ao=None, ao_strength=0.85):
    """Rasterize items, run rules(P, N, PART) -> (lin rgb, rough, metal, height), write images."""
    P, N, PART, MASK = rasterize(items, W, H)
    full = dilate(MASK, [P, N, PART], iters=6)
    idx = np.nonzero(full)
    col, rough, metal, height = rules(P[idx], N[idx], PART[idx])
    if ao is not None:
        col = col * (1.0 - ao_strength * (1.0 - ao[idx]))[:, None]
    base = np.zeros((H, W, 3), np.float32)
    orm = np.zeros((H, W, 3), np.float32)
    hgt = np.zeros((H, W), np.float32)
    base[idx] = lin_to_srgb(col)
    orm[..., 0] = 1.0
    orm[idx + (1,)] = rough
    orm[idx + (2,)] = metal
    hgt[idx] = height
    nrm = normal_from_height(hgt, normal_strength)
    for key, data in (("base", base), ("orm", orm), ("normal", nrm)):
        write_image(imgs[key], data)
        if out_dir:
            save_image(imgs[key], f"{out_dir}/{imgs[key].name}.png")
    return int(MASK.sum())
