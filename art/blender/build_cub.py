"""Builds the Cub-type airframe in Blender and exports game/aircraft/J3Cub/model/cub.glb.

Run inside Blender:
    p = "<repo>/art/blender/build_cub.py"; exec(compile(open(p).read(), p, "exec"), {"__file__": p})

Frame: Blender X = right, Y = forward, Z = up, metres. Origin = JSBSim structural
origin, so the glTF lands in Godot exactly on Geo.struct_to_local (JSBSim x aft,
y right, z up, inches -> Blender (y, -x, z) * 0.0254). Dimensions from J3Cub.xml
(gear, prop, eyepoint, wing, tail arms) and published J-3 figures.

Node names follow game/aircraft/model_airframe.gd (hinges, Prop, Wheel_*, Steer_*).
"""
import bpy, bmesh, math, os, sys, importlib
import numpy as np
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_tools as pt
importlib.reload(pt)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "game", "aircraft", "J3Cub", "model", "cub.glb")
TEX_DIR = os.path.join(REPO, "art", "blender", "out")  # PNG copies for inspection (not committed)
# Texture sizes; drop QUALITY to 0.5 while iterating.
QUALITY = globals().get("QUALITY", 1.0)
TEX = {"fus": (2048, 1024), "wing": (4096, 1024), "tail": (2048, 1024)}
REG = "N7283K"

# --- materials ---------------------------------------------------------------

def lin(h):
    f = lambda u: u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4
    return tuple(f(int(h[i:i + 2], 16) / 255) for i in (1, 3, 5)) + (1.0,)


def material(name, hexcol, rough=0.8, metal=0.0, alpha=1.0, double=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = lin(hexcol)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Alpha"].default_value = alpha
    m.diffuse_color = lin(hexcol)[:3] + (alpha,)
    if alpha < 1.0:
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    m.use_backface_culling = not double
    return m


M, IMGS = {}, {}
def make_materials():
    M["blue"] = material("Paint_Blue", "#4E7D96", 0.7)
    M["cream"] = material("Fabric_Cream", "#E3D9BF", 0.85)
    M["glass"] = material("Glass", "#C8D4D4", 0.05, alpha=0.18, double=True)
    M["interior"] = material("Interior_Fabric", "#8A8068", 0.9)
    M["engine"] = material("Engine_Black", "#1A1A1A", 0.55, 0.6)
    M["exhaust"] = material("Exhaust_Rust", "#5A3420", 0.7, 0.5)
    M["steel"] = material("Steel", "#8C8C8C", 0.45, 1.0)
    M["tyre"] = material("Tyre", "#141414", 0.92)
    M["prop"] = material("Prop_Black", "#151515", 0.5)
    M["tip"] = material("Prop_Tip", "#E8B830", 0.5)
    M["disc"] = material("Prop_Disc", "#202020", 0.5, alpha=0.08, double=True)
    M["reg"] = material("Registration", "#E2DAC2", 0.7, double=True)
    M["blue"] = material("Paint_Blue", "#557A8C", 0.7)
    for key, (w, h) in TEX.items():
        M["tex_" + key], IMGS[key] = pt.textured_material("Cub_" + key.capitalize(),
                                                         int(w * QUALITY), int(h * QUALITY))

# --- mesh building -------------------------------------------------------------

class MB:
    """Vertices + faces with a material key per face."""
    def __init__(self):
        self.v, self.f, self.m, self.uv = [], [], [], []

    def vert(self, p, uv=(0.0, 0.0)):
        self.v.append(tuple(p))
        self.uv.append(tuple(uv))
        return len(self.v) - 1

    def face(self, idx, mat):
        self.f.append(list(idx))
        self.m.append(mat)

    def ring(self, pts, uvs=None):
        return [self.vert(p, uvs[i] if uvs else (0.0, 0.0)) for i, p in enumerate(pts)]

    def loft(self, rings, mat, cap0=False, cap1=False, closed=True):
        """rings: lists of vertex indices, equal length. mat(i, j) or a key."""
        mf = mat if callable(mat) else (lambda i, j: mat)
        n = len(rings[0])
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            for j in range(n if closed else n - 1):
                k = (j + 1) % n
                self.face((a[j], a[k], b[k], b[j]), mf(i, j))
        if cap0:
            self.face(list(reversed(rings[0])), mf(0, 0))
        if cap1:
            self.face(rings[-1], mf(len(rings) - 2, 0))


COLL = None
def obj(name, mb, parent=None, recalc=True, smooth=35.0):
    keys = list(dict.fromkeys(mb.m))
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.v, [], mb.f)
    for k in keys:
        me.materials.append(M[k])
    for poly, k in zip(me.polygons, mb.m):
        poly.material_index = keys.index(k)
    me.validate()
    uvl = me.uv_layers.new(name="UVMap")
    vi = [0] * len(me.loops)
    me.loops.foreach_get("vertex_index", vi)
    flat = []
    for v in vi:
        flat += mb.uv[v]
    uvl.data.foreach_set("uv", flat)
    if recalc:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
    me.shade_smooth()
    if smooth:
        me.set_sharp_from_angle(angle=math.radians(smooth))
    ob = bpy.data.objects.new(name, me)
    COLL.objects.link(ob)
    if parent:
        set_parent(ob, parent)
    return ob


def empty(name, loc, rot=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.15
    e.location = loc
    e.rotation_euler = rot
    COLL.objects.link(e)
    if parent:
        set_parent(e, parent)
    bpy.context.view_layer.update()
    return e


def set_parent(child, parent):
    bpy.context.view_layer.update()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def lerp(a, b, t):
    return a + (b - a) * t


def interp(table, y, col):
    """Piecewise-linear lookup in rows sorted by descending y (first column)."""
    for r0, r1 in zip(table, table[1:]):
        if r0[0] >= y >= r1[0]:
            t = (r0[0] - y) / (r0[0] - r1[0]) if r0[0] != r1[0] else 0.0
            return lerp(r0[col], r1[col], t)
    return table[0][col] if y > table[0][0] else table[-1][col]


def tube(mb, pts, r, mat, sides=8, cap=True, squash=1.0, flat_axis=None):
    """Tube along a polyline. squash < 1 flattens it across `flat_axis` (default: vertical)."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector(flat_axis) if flat_axis else (Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0)))
        u = d.cross(up).normalized()
        w = d.cross(u).normalized()
        rings.append(mb.ring([p + (u * math.cos(a) + w * math.sin(a) * squash) * r
                              for a in [k * 2 * math.pi / sides for k in range(sides)]]))
    mb.loft(rings, mat, cap0=cap, cap1=cap)


def lathe(mb, profile, mat, axis_pt, axis="x", sides=16, sign=1.0):
    """Revolve [(along, radius)] around an axis through axis_pt."""
    c = Vector(axis_pt)
    mf = mat if callable(mat) else (lambda i, j: mat)

    def on_axis(a_):
        return c + {"x": Vector((sign * a_, 0, 0)), "y": Vector((0, sign * a_, 0)),
                    "z": Vector((0, 0, sign * a_))}[axis]

    tip0 = mb.vert(on_axis(profile[0][0])) if profile[0][1] == 0 else None
    tip1 = mb.vert(on_axis(profile[-1][0])) if profile[-1][1] == 0 else None
    body = [pr for pr in profile if pr[1] > 0]
    rings = []
    for a_, r in body:
        pts = []
        for k in range(sides):
            t = k * 2 * math.pi / sides
            if axis == "x":
                pts.append(c + Vector((sign * a_, r * math.cos(t), r * math.sin(t))))
            elif axis == "y":
                pts.append(c + Vector((r * math.cos(t), sign * a_, r * math.sin(t))))
            else:
                pts.append(c + Vector((r * math.cos(t), r * math.sin(t), sign * a_)))
        rings.append(mb.ring(pts))
    mb.loft(rings, mf, cap0=tip0 is None, cap1=tip1 is None)
    for tip, rg in ((tip0, rings[0]), (tip1, rings[-1])):
        if tip is not None:
            for k in range(sides):
                mb.face((rg[k], rg[(k + 1) % sides], tip), mf(0, 0))

# --- fuselage ----------------------------------------------------------------

# y, width, z bottom, z top, [window bottom, window top]
FUS = [
    (1.68, 0.30, -0.78, -0.46),
    (1.60, 0.50, -0.90, -0.34),
    (1.45, 0.60, -0.98, -0.27),
    (1.20, 0.65, -1.03, -0.235),
    (1.00, 0.66, -1.06, -0.22, -0.27, -0.245),
    (0.80, 0.66, -1.08, -0.15, -0.36, -0.17),
    (0.42, 0.66, -1.10, -0.015, -0.52, -0.07),
    (0.00, 0.66, -1.10, -0.015, -0.52, -0.065),
    (-0.95, 0.65, -1.07, -0.02, -0.52, -0.07),
    (-1.20, 0.63, -1.05, -0.03),
    (-1.60, 0.58, -1.01, -0.10),
    (-2.50, 0.44, -0.93, -0.28),
    (-3.50, 0.27, -0.84, -0.46),
    (-4.30, 0.13, -0.73, -0.565),
    (-4.62, 0.035, -0.665, -0.60),
]
FUS = [r if len(r) == 6 else r + (r[2] + 0.70 * (r[3] - r[2]), r[2] + 0.90 * (r[3] - r[2])) for r in FUS]
EXTRA_Y = [0.97, 0.90, 0.70, 0.60, 0.50, 0.40, 0.36, 0.20, -0.15, -0.30, -0.34, -0.60,
           -2.0, -3.0, -3.9, 1.10, 1.30, 1.53, 1.64]
STATIONS = sorted(set([r[0] for r in FUS] + EXTRA_Y), reverse=True)


def fus_at(y):
    return [interp(FUS, y, c) for c in range(1, 6)]


def half_width(y):
    return 0.5 * interp(FUS, y, 1)


def section(y, inset=0.0):
    w, zb, zt, zwb, zwt = fus_at(y)
    w -= 2 * inset
    zb += inset
    zt -= inset
    h = zt - zb
    zs = zb + 0.45 * h
    right = [(0, zb), (0.40 * w, zb), (0.5 * w, zb + min(0.06, 0.15 * h)), (0.5 * w, zs),
             (0.5 * w, zs + 0.025), (0.5 * w, zs + 0.045), (0.5 * w, zwb), (0.47 * w, zwt),
             (0.33 * w, zt - 0.012), (0.17 * w, zt - 0.003), (0, zt)]
    ring = right + [(-x, z) for x, z in reversed(right[1:-1])]
    return [Vector((x, y, z)) for x, z in ring]


def band_of(j, n_right=11):
    return j if j < n_right - 1 else 2 * (n_right - 1) - 1 - j


def windshield(y):
    return 0.42 < y < 0.97


def side_window(y):
    return -0.95 < y < 0.36 and not (-0.34 < y < -0.30)


def fus_material(y, band):
    if band == 6:
        return "glass" if (windshield(y) or side_window(y)) else "tex_fus"
    if band >= 7:
        return "glass" if windshield(y) else "tex_fus"
    return "tex_fus"


FUS_Y0, FUS_LEN = 1.72, 6.34


def fus_uv_ring(pts, y):
    """Closed section + repeated first point; u along the fuselage, v around it."""
    ring = pts + [pts[0]]
    arc = [0.0]
    for a, b in zip(ring, ring[1:]):
        arc.append(arc[-1] + (b - a).length)
    u = 0.01 + 0.98 * (FUS_Y0 - y) / FUS_LEN
    return ring, [(u, 0.01 + 0.98 * a / arc[-1]) for a in arc]


def build_fuselage(root):
    mb = MB()
    rings = [mb.ring(*fus_uv_ring(section(y), y)) for y in STATIONS]
    mid = [(STATIONS[i] + STATIONS[i + 1]) / 2 for i in range(len(STATIONS) - 1)]
    mb.loft(rings, lambda i, j: fus_material(mid[i], band_of(j)), cap1=True, closed=False)
    first = rings[0]
    for j in range(len(first) - 1):
        nose = mb.vert((0, FUS_Y0, -0.62), (0.005, mb.uv[first[j]][1]))
        mb.face((first[j + 1], first[j], nose), "tex_fus")
    obj("Fuselage", mb, root, smooth=55)

    # Cabin lining seen from the seats: inset, inward-facing, no faces over the glass.
    ib = MB()
    cab = [y for y in STATIONS if 1.0 >= y >= -1.6]
    irings = [ib.ring(section(y, 0.012)) for y in cab]
    n = len(irings[0])
    for i in range(len(cab) - 1):
        ym = (cab[i] + cab[i + 1]) / 2
        for j in range(n):
            if fus_material(ym, band_of(j)) == "glass":
                continue
            k = (j + 1) % n
            a, b = irings[i], irings[i + 1]
            ib.face((b[j], b[k], a[k], a[j]), "interior")
    ib.face(irings[0], "interior")
    ib.face(list(reversed(irings[-1])), "interior")
    obj("Interior", ib, root, recalc=False, smooth=40)

# --- lifting surfaces ----------------------------------------------------------

def naca4412(x, chord):
    m, p, t = 0.04, 0.4, 0.12
    yt = 5 * t * (0.2969 * math.sqrt(max(x, 0)) - 0.1260 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 - 0.1036 * x ** 4)
    yc = m / p ** 2 * (2 * p * x - x * x) if x < p else m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x * x)
    return (yc + yt) * chord, (yc - yt) * chord


def slab(t_root, blunt_front=False, taper_back=True, x0=0.0):
    """Thin tail-surface section: rounded or blunt front, tapering from x0 to the trailing edge."""
    def f(x, chord):
        T = t_root * min(1.0, chord / 0.45)
        nose = 1.0 if blunt_front else min(1.0, math.sqrt(max(x, 0) / 0.12))
        tail = (1.0 - 0.85 * (x - x0) / (1.0 - x0)) if taper_back else 1.0
        h = T * nose * tail
        return h, -h
    return f


def surface(mb, stations, c0, c1, profile, mapper, mat, n=12, uvf=None, hidden=None):
    """stations: [(s, le, te)], chord along Y (le > te). Closed loft between c0..c1.
    Each ring runs lower TE -> LE -> upper TE, so the UV seam sits on the trailing edge.
    uvf(s, y, x, upper) -> (u, v). Caps and blunt hinge walls get `hidden` (untextured)."""
    xs = [c0 + (c1 - c0) * (0.5 - 0.5 * math.cos(math.pi * k / (n - 1))) for k in range(n)]
    rings, blunt_back, blunt_front, n_lo = [], False, False, n
    for s, le, te in stations:
        chord = max(le - te, 1e-4)
        lo = [(x, profile(x, chord)[1], False) for x in reversed(xs)]
        up = [(x, profile(x, chord)[0], True) for x in xs]
        blunt_front = abs(up[0][1] - lo[-1][1]) > 1e-6
        if not blunt_front:
            up = up[1:]
        blunt_back = abs(up[-1][1] - lo[0][1]) > 1e-6
        pts = [mapper(s, le - x * chord, z) for x, z, _ in lo + up]
        uvs = [uvf(s, le - x * chord, x, u) for x, _, u in lo + up] if uvf else None
        rings.append(mb.ring(pts, uvs))
    mf = mat if callable(mat) else (lambda i, j: mat)
    hid = hidden or mf(0, 0)
    mb.loft(rings, lambda i, j: hid if (blunt_front and j == n_lo - 1) else mf(i, j), closed=False)
    if blunt_back:
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            mb.face((a[-1], a[0], b[0], b[-1]), hid)
    mb.face(list(reversed(rings[0])), hid)
    mb.face(rings[-1], hid)
    return rings


def chord_uv(u0, du, s_len, v0, dv, x0=0.0, x1=1.0, mirror=1.0):
    """UV for a chord-parametrised surface: u along span, v around the section
    (lower TE at v0, leading edge mid-way, upper TE at v0 + dv)."""
    def f(s, y, x, upper):
        t = (x - x0) / (x1 - x0) if x1 > x0 else 0.0
        v = v0 + dv * (0.5 + 0.5 * t if upper else 0.5 - 0.5 * t)
        return (u0 + du * min(abs(s) / s_len, 1.0), v)
    return f


INC, DIH = math.radians(2.0), math.radians(1.0)
WING_LE, WING_TE, TIP0, HALF = 0.40, -1.20, 4.95, 5.37
AIL0, AIL1, AIL_C = 2.55, 4.85, 0.785


def wing_mapper(side):
    def f(s, y, z):
        yr = y * math.cos(INC) - z * math.sin(INC)
        zr = y * math.sin(INC) + z * math.cos(INC)
        return Vector((side * s, yr, zr + s * math.tan(DIH)))
    return f


def wing_station(s):
    if s <= TIP0:
        return (s, WING_LE, WING_TE)
    hc = 0.80 * math.sqrt(max(0.0, 1 - ((s - TIP0) / (HALF - TIP0)) ** 2))
    hc = max(hc, 0.01)
    mid = 0.5 * (WING_LE + WING_TE)
    return (s, mid + hc, mid - hc)


def build_wing(root):
    mb = MB()
    tip_s = [4.85, 4.95, 5.05, 5.15, 5.23, 5.29, 5.33, 5.36, 5.37]
    for side in (1, -1):
        mp = wing_mapper(side)
        uv = chord_uv(0.005 if side > 0 else 0.505, 0.49, HALF, 0.01, 0.76)
        for st, c1, n in (([0.0, 0.5, 1.0, 1.6, 2.1, AIL0], 1.0, 16), ([AIL0, 3.2, 4.0, AIL1], AIL_C, 14), (tip_s, 1.0, 16)):
            surface(mb, [wing_station(s) for s in st], 0.0, c1, naca4412, mp, "tex_wing", n, uv, "cream")
    obj("Wing", mb, root, smooth=50)

    for side, tag in ((1, "R"), (-1, "L")):
        mp = wing_mapper(side)
        y_h = WING_LE - AIL_C * (WING_LE - WING_TE)
        zc = sum(naca4412(AIL_C, WING_LE - WING_TE)) / 2
        hinge = empty("Hinge_aileron_" + tag, mp(AIL0 + 0.02, y_h, zc), (0, -side * DIH, 0), root)
        ab = MB()
        uv = chord_uv(0.005 if side > 0 else 0.505, 0.49, HALF, 0.80, 0.19, AIL_C + 0.005, 1.0)
        surface(ab, [wing_station(s) for s in [AIL0 + 0.02, 3.2, 4.0, AIL1 - 0.02]], AIL_C + 0.005, 1.0,
                naca4412, mp, "tex_wing", 8, uv, "cream")
        obj("Aileron_" + tag, ab, hinge, smooth=50)


def ellip(s, s0, s1):
    return math.sqrt(max(0.0, 1 - ((s - s0) / (s1 - s0)) ** 2)) if s > s0 else 1.0


STAB_Z, STAB_HINGE, FIN_Z0, RUD_HINGE = -0.585, -4.30, -0.60, -4.62


def build_tail(root):
    def stab_station(s):
        e = ellip(s, 1.05, 1.45)
        return (s, STAB_HINGE + 0.50 * e, STAB_HINGE - 0.30 * e)

    h = 0.5 / 0.8
    st = [0.0, 0.3, 0.6, 0.9, 1.05, 1.15, 1.25, 1.33, 1.39, 1.43, 1.449]
    sb, eb = MB(), MB()
    for side in (1, -1):
        mp = lambda s, y, z, side=side: Vector((side * s, y, STAB_Z + z))
        u0 = 0.005 if side > 0 else 0.255
        surface(sb, [stab_station(s) for s in st], 0.0, h, slab(0.022, taper_back=False), mp, "tex_tail", 10,
                chord_uv(u0, 0.24, 1.45, 0.01, 0.98), "cream")
        surface(eb, [stab_station(s) for s in [0.07] + st[1:]], h, 1.0, slab(0.022, True, x0=h), mp, "tex_tail", 6,
                chord_uv(u0, 0.24, 1.45, 0.01, 0.98), "cream")
    obj("Stabilizer", sb, root, smooth=50)
    hinge = empty("Hinge_elevator", (0, STAB_HINGE, STAB_Z), parent=root)
    obj("Elevator", eb, hinge, smooth=50)

    def fin_le(s):
        if s <= 0.80:
            return -3.85 - 0.45 * s / 0.80
        return RUD_HINGE + 0.32 * math.sqrt(max(0.0, 1 - ((s - 0.80) / 0.18) ** 2))

    def rud_te(s):
        if s < -0.03:
            return lerp(-4.94, -5.00, (s + 0.07) / 0.04)
        if s <= 0.55:
            return -5.02
        return RUD_HINGE - 0.40 * math.sqrt(max(0.0, 1 - ((s - 0.55) / 0.43) ** 2))

    vmap = lambda s, y, z: Vector((z, y, FIN_Z0 + s))

    def side_uv(s, y, x, right):
        """Fin and rudder: side projection, right side and left side in separate tiles."""
        return ((0.505 if right else 0.755) + 0.24 * (-3.78 - y) / 1.30, 0.01 + 0.98 * (s + 0.15) / 1.15)

    fb, rb = MB(), MB()
    fs = [0.0, 0.2, 0.4, 0.6, 0.8, 0.86, 0.91, 0.95, 0.975, 0.979]
    surface(fb, [(s, fin_le(s), RUD_HINGE) for s in fs], 0.0, 1.0, slab(0.018, taper_back=False), vmap,
            "tex_tail", 10, side_uv, "cream")
    rs = [-0.07, -0.03, 0.1, 0.3, 0.55, 0.65, 0.75, 0.84, 0.91, 0.95, 0.975, 0.979]
    surface(rb, [(s, RUD_HINGE, rud_te(s)) for s in rs], 0.0, 1.0, slab(0.018, True), vmap,
            "tex_tail", 8, side_uv, "cream")
    obj("Fin", fb, root, smooth=50)
    hinge = empty("Hinge_rudder", (0, RUD_HINGE, FIN_Z0), (0, math.radians(90), 0), root)
    obj("Rudder", rb, hinge, smooth=50)


# --- struts, gear, engine, prop --------------------------------------------------

def wing_bottom(side, s, chord_frac):
    return wing_mapper(side)(s, WING_LE - chord_frac * (WING_LE - WING_TE),
                             naca4412(chord_frac, WING_LE - WING_TE)[1])


def build_struts(root):
    mb = MB()
    for side in (1, -1):
        foot = Vector((side * 0.32, -0.10, -1.03))
        front = wing_bottom(side, 2.10, 0.15)
        rear = wing_bottom(side, 2.10, 0.65)
        # Streamlined (teardrop-flat) section, long axis along the airflow.
        tube(mb, [foot, front], 0.027, "blue", 10, squash=0.42)
        tube(mb, [foot + Vector((0, -0.04, 0)), rear], 0.027, "blue", 10, squash=0.42)
        for p in (front, rear):
            box(mb, p + Vector((0, 0, -0.012)), (0.05, 0.06, 0.02), "steel")  # wing fittings
        for top, bot in ((front, foot), (rear, foot + Vector((0, -0.04, 0)))):
            mid = bot.lerp(top, 0.6)
            tube(mb, [mid, wing_bottom(side, 1.62, 0.15 if top is front else 0.65)], 0.008, "steel", 6)
    obj("Struts", mb, root, smooth=60)


# Uncompressed contact points from J3Cub.xml: mains z -74.18 in, tail z -35.70 in.
AXLE_Y, AXLE_Z, AXLE_X = 0.32, -74.18 * 0.0254 + 0.255, 0.91
TYRE_R, TYRE_W = 0.255, 0.18
TAIL_R = 0.083
TAIL_AXLE = Vector((0, -4.81, -35.70 * 0.0254 + TAIL_R))
TAIL_PIVOT = Vector((0, -4.78, TAIL_AXLE.z + 0.075))


def tyre(mb, r_out, width, sides=24, minor=10, hub_r=None):
    """Tyre around the local X axis, centred on the origin."""
    R = r_out - width / 2
    rings = []
    for i in range(sides):
        t = i * 2 * math.pi / sides
        c = Vector((0, R * math.cos(t), R * math.sin(t)))
        radial = Vector((0, math.cos(t), math.sin(t)))
        rings.append(mb.ring([c + radial * (width / 2) * math.cos(p) + Vector((1, 0, 0)) * (width / 2) * math.sin(p)
                              for p in [k * 2 * math.pi / minor for k in range(minor)]]))
    rings.append(rings[0])
    mb.loft(rings, "tyre")
    hub_r = hub_r or R * 0.75
    lathe(mb, [(-width * 0.38, 0), (-width * 0.38, hub_r), (width * 0.38, hub_r), (width * 0.38, 0)],
          "steel", (0, 0, 0), "x", 16)


def link(name, anchor, parent, build):
    """A part that the game turns (and for Stretch-*, stretches) so it keeps reaching its
    target node: name 'Link-<target>-<n>' or 'Stretch-<target>-<n>', origin = fixed end."""
    e = empty(name, tuple(anchor), parent=parent)
    mb = MB()
    build(mb)
    obj(name.replace("-", "_") + "_mesh", mb, e, smooth=60)
    return e


def build_gear(root):
    mb = MB()
    for side in (1, -1):
        # Fittings on the fuselage and the centre hinge of the split axles.
        for c in ((side * 0.33, 0.50, -1.04), (side * 0.33, -0.10, -1.04)):
            box(mb, c, (0.03, 0.05, 0.03), "blue")
    box(mb, (0, AXLE_Y, -1.13), (0.07, 0.06, 0.04), "steel")
    # Tail post fitting for the leaf spring.
    box(mb, (0, -4.40, -0.72), (0.04, 0.08, 0.03), "steel")
    obj("Gear_fixed", mb, root, smooth=60)

    for side, tag in ((1, "R"), (-1, "L")):
        axle = Vector((side * AXLE_X, AXLE_Y, AXLE_Z))
        inner = axle - Vector((side * 0.11, 0, 0))
        w = empty("Wheel_" + tag, tuple(axle), parent=root)
        wb = MB()
        tyre(wb, TYRE_R, TYRE_W, hub_r=0.10)
        for k in range(6):  # hub bolts
            a = k * math.pi / 3
            lathe(wb, [(0.0, 0), (0.0, 0.011), (0.012, 0.011), (0.012, 0)], "steel",
                  (side * TYRE_W * 0.38, 0.06 * math.cos(a), 0.06 * math.sin(a)), "x", 6, side)
        wb.v = [tuple(Vector(p) + axle) for p in wb.v]
        obj("Tyre_" + tag, wb, w, smooth=60)
        empty("Axle_" + tag, tuple(inner), parent=w)  # on the spin axis, so spinning doesn't move it

        hinge = Vector((side * 0.03, AXLE_Y, -1.13))
        rear = Vector((side * 0.33, -0.10, -1.04))
        top = Vector((side * 0.33, 0.50, -1.04))
        link(f"Stretch-Axle_{tag}-1", hinge, root, lambda m: tube(m, [hinge, inner], 0.021, "blue"))
        link(f"Stretch-Axle_{tag}-2", rear, root, lambda m: tube(m, [rear, inner], 0.019, "blue"))
        # Shock strut: bungee sleeve at the top (turns), sliding rod below (turns + stretches).
        def sleeve(m, top=top, inner=inner, side=side):
            tube(m, [top.lerp(inner, 0.08), top.lerp(inner, 0.45)], 0.034, "blue", 10)
            for f in (0.17, 0.23, 0.29, 0.35):  # bungee cord wraps
                lathe(m, [(-0.012, 0), (-0.012, 0.042), (0.012, 0.042), (0.012, 0)], "tyre",
                      top.lerp(inner, f), "x", 10)
            if side > 0:  # step for climbing in, right side
                box(m, top.lerp(inner, 0.55) + Vector((0.05, 0, 0)), (0.07, 0.05, 0.006), "steel")
        link(f"Link-Axle_{tag}-3", top, root, sleeve)
        link(f"Stretch-Axle_{tag}-4", top, root, lambda m, top=top, inner=inner: tube(m, [top, inner], 0.016, "steel"))
        link(f"Stretch-Axle_{tag}-5", top + Vector((0, -0.03, 0)), root,  # brake line
             lambda m, top=top, inner=inner: tube(m, [top + Vector((0, -0.03, 0)), inner + Vector((0, -0.04, 0.03))],
                                                  0.004, "tyre", 5))

    # Tailwheel: steering pivot carries the fork, wheel and steering horn; the leaf
    # spring and the steering springs from the rudder horn follow it.
    steer = empty("Steer_tail", tuple(TAIL_PIVOT), parent=root)
    fb = MB()
    for sx in (0.028, -0.028):
        tube(fb, [TAIL_PIVOT, TAIL_PIVOT + Vector((sx, -0.02, -0.04)), TAIL_AXLE + Vector((sx, 0, 0))], 0.007, "steel", 6)
    lathe(fb, [(-0.02, 0), (-0.02, 0.014), (0.03, 0.014), (0.03, 0)], "steel", TAIL_PIVOT, "z", 8)
    tube(fb, [TAIL_PIVOT + Vector((-0.07, 0.01, 0.02)), TAIL_PIVOT + Vector((0.07, 0.01, 0.02))], 0.006, "steel", 6)
    obj("Tail_fork", fb, steer, smooth=60)
    for sx, tag in ((-0.07, "L"), (0.07, "R")):
        empty("THorn_" + tag, tuple(TAIL_PIVOT + Vector((sx, 0.01, 0.02))), parent=steer)
    tw = empty("Wheel_T", tuple(TAIL_AXLE), parent=steer)
    tb = MB()
    tyre(tb, TAIL_R, 0.04, 16, 8, hub_r=0.03)
    tb.v = [tuple(Vector(p) + TAIL_AXLE) for p in tb.v]
    obj("Tyre_T", tb, tw, smooth=60)
    leaf0 = Vector((0, -4.40, -0.735))
    link("Stretch-Steer_tail-1", leaf0, root,
         lambda m: tube(m, [leaf0, TAIL_PIVOT + Vector((0, 0, 0.02))], 0.022, "steel", 8, squash=0.3))


def box(mb, c, size, mat):
    c = Vector(c)
    hx, hy, hz = (v / 2 for v in size)
    vi = [mb.vert(c + Vector((sx * hx, sy * hy, sz * hz))) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        mb.face([vi[i] for i in f], mat)


def build_controls(root):
    """Control horns, cables and tailwheel steering springs (all follow the moving parts)."""
    O = bpy.data.objects
    rud, elev = O["Hinge_rudder"], O["Hinge_elevator"]
    hb = MB()
    tube(hb, [(-0.09, -4.66, -0.672), (0.09, -4.66, -0.672)], 0.007, "steel", 6)  # rudder horn
    obj("Rudder_horn", hb, rud, smooth=60)
    eb = MB()
    for dz in (0.06, -0.06):
        tube(eb, [(0.10, -4.31, STAB_Z), (0.10, -4.28, STAB_Z + dz)], 0.006, "steel", 6)  # elevator horns
    obj("Elevator_horns", eb, elev, smooth=60)
    for sx, tag in ((-0.09, "L"), (0.09, "R")):
        horn = Vector((sx, -4.66, -0.672))
        e = empty("RHorn_" + tag, tuple(horn), parent=rud)
        thorn = Vector((sx * 0.78, -4.77, TAIL_PIVOT.z + 0.02))
        link(f"Stretch-THorn_{tag}-1", horn, rud,  # steering spring + chain
             lambda m, horn=horn, thorn=thorn: tube(m, [horn, thorn], 0.006, "steel", 6))
        fair = empty("Fair_rud_" + tag, (sx * 0.9, -3.95, -0.80), parent=root)
        link(f"Stretch-RHorn_{tag}-2", fair.location, root,  # rudder cable into the fuselage
             lambda m, a=fair.location.copy(), b=horn: tube(m, [a, b], 0.0025, "steel", 4))
    for dz, tag in ((0.06, "T"), (-0.06, "B")):
        tip = Vector((0.10, -4.28, STAB_Z + dz))
        empty("EHorn_" + tag, tuple(tip), parent=elev)
        a = Vector((0.06, -3.95, STAB_Z + dz * 0.8))
        empty("Fair_elev_" + tag, tuple(a), parent=root)
        link(f"Stretch-EHorn_{tag}-1", a, root, lambda m, a=a, tip=tip: tube(m, [a, tip], 0.0025, "steel", 4))


def build_details(root):
    """Small parts: tail brace wires, fuel gauge, intakes, pitot, tie-downs, door handle."""
    mb = MB()
    for side in (1, -1):
        fin_pt = Vector((0, -4.42, FIN_Z0 + 0.52))
        stab_top = Vector((side * 0.78, -4.15, STAB_Z + 0.02))
        stab_bot = Vector((side * 0.78, -4.15, STAB_Z - 0.02))
        fus_bot = Vector((side * 0.035, -4.38, -0.72))
        tube(mb, [fin_pt, stab_top], 0.0035, "steel", 4)
        tube(mb, [stab_bot, fus_bot], 0.0035, "steel", 4)
        for p in (stab_top, stab_bot):
            box(mb, p, (0.02, 0.02, 0.006), "steel")
        # Tie-down ring under each wing.
        lathe(mb, [(-0.004, 0.012), (-0.004, 0.022), (0.004, 0.022), (0.004, 0.012)], "steel",
              wing_bottom(side, 3.0, 0.40) + Vector((0, 0, -0.03)), "y", 8)
        # Nose bowl air intakes either side of the spinner.
        lathe(mb, [(-0.002, 0), (-0.002, 0.042), (0.004, 0.042), (0.004, 0)], "engine",
              (side * 0.085, 1.684, -0.57), "y", 12)
    # Fuel tank cap with the cork-float wire gauge in front of the windscreen.
    lathe(mb, [(0, 0), (0, 0.035), (0.022, 0.035), (0.022, 0)], "steel", (0, 0.93, -0.226), "z", 12)
    tube(mb, [(0, 0.93, -0.20), (0, 0.93, 0.02), (0, 0.97, 0.02)], 0.003, "steel", 5)
    # Carburettor air scoop under the cowl.
    box(mb, (0, 1.30, -1.045), (0.12, 0.18, 0.06), "engine")
    # Pitot tube under the left wing.
    base = wing_bottom(-1, 3.4, 0.25)
    tube(mb, [base, base + Vector((0, 0, -0.10)), base + Vector((0, 0.18, -0.10))], 0.006, "steel", 6)
    # Door handle, right side.
    box(mb, (0.336, -0.22, -0.62), (0.012, 0.07, 0.015), "steel")
    obj("Details", mb, root, smooth=50)


PROP = Vector((0, 1.75, -0.62))
PROP_R = 0.915


def build_engine(root):
    mb = MB()
    fins = []
    for k in range(10):
        fins += [(k * 0.016, 0.058), (k * 0.016 + 0.008, 0.078)]
    for side in (1, -1):
        for y in ((1.28, 1.48) if side > 0 else (1.38, 1.58)):
            hw = half_width(y)
            base = Vector((side * (hw - 0.07), y, -0.50))
            lathe(mb, [(0, 0)] + fins + [(0.16, 0.058), (0.16, 0)], "engine", base, "x", 12, side)
            head = base + Vector((side * 0.16, 0, 0))
            hfins = []
            for k in range(6):
                hfins += [(k * 0.014, 0.072), (k * 0.014 + 0.007, 0.092)]
            lathe(mb, [(0, 0)] + hfins + [(0.085, 0.07), (0.10, 0.05), (0.10, 0)], "engine", head, "x", 14, side)
            rocker = head + Vector((side * 0.05, 0, 0.075))
            rb = [rocker + Vector((sx * 0.045, sy * 0.05, sz * 0.022)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            vi = [mb.vert(p) for p in rb]
            for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                mb.face([vi[i] for i in f], "steel")
        hw = half_width(1.0)
        tube(mb, [(side * (half_width(1.53) + 0.03), 1.53, -0.60), (side * (half_width(1.40) + 0.04), 1.40, -0.67),
                  (side * (hw + 0.03), 1.05, -0.67), (side * (hw + 0.02), 0.92, -0.72)], 0.024, "exhaust", 10)
    obj("Engine", mb, root, smooth=45)


def build_prop(root):
    p = empty("Prop", tuple(PROP), parent=root)
    pitch = 45 * 0.0254

    def chord(r):
        if r < 0.35:
            return lerp(0.07, 0.13, (r - 0.06) / 0.29)
        if r < 0.80:
            return lerp(0.13, 0.11, (r - 0.35) / 0.45)
        return 0.11 * math.sqrt(max(0.05, 1 - ((r - 0.80) / (PROP_R - 0.80)) ** 2))

    bb = MB()
    rs = [0.06, 0.12, 0.2, 0.35, 0.5, 0.65, 0.78, 0.83, 0.87, 0.895, 0.91, PROP_R]
    for blade in (1, -1):
        rings = []
        for r in rs:
            beta = math.atan(pitch / (2 * math.pi * max(r, 0.15)))
            c = chord(r)
            tk = c * lerp(0.28, 0.08, r / PROP_R)
            d = Vector((math.cos(beta), math.sin(beta), 0))
            nrm = Vector((-math.sin(beta), math.cos(beta), 0))
            pts = []
            for k in range(10):
                a = k * 2 * math.pi / 10
                u, v = 0.5 * c * math.cos(a), 0.5 * tk * math.sin(a) * (1.0 if math.sin(a) > 0 else 0.5)
                q = d * u + nrm * v + Vector((0, 0, r))
                pts.append(PROP + Vector((blade * q.x, q.y, blade * q.z)))
            rings.append(bb.ring(pts))
        bb.loft(rings, lambda i, j: "tip" if rs[i] >= 0.83 else "prop", cap1=True)
    obj("Blades", bb, p, smooth=50)

    sb = MB()
    lathe(sb, [(-0.04, 0), (-0.04, 0.085), (0.02, 0.083), (0.08, 0.06), (0.13, 0.03), (0.16, 0)],
          "steel", PROP, "y", 16)
    obj("Spinner", sb, p, smooth=60)

    db = MB()
    lathe(db, [(-0.002, 0), (-0.002, PROP_R), (0.002, PROP_R), (0.002, 0)], "disc", PROP, "y", 48)
    obj("Disc", db, p, smooth=0)


def build_registration(root):
    for side in (1, -1):
        cu = bpy.data.curves.new("reg_text", "FONT")
        cu.body = REG
        cu.size = 0.25
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        tmp = bpy.data.objects.new("reg_tmp", cu)
        COLL.objects.link(tmp)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(tmp)
        bpy.data.curves.remove(cu)
        y, z = -2.05, -0.755
        slope = (half_width(y + 0.3) - half_width(y - 0.3)) / 0.6
        along = Vector((side * slope, 1.0, 0)).normalized() * side
        up = Vector((0, 0, 1))
        normal = along.cross(up)
        loc = Vector((side * (half_width(y) + 0.004), y, z))
        mat = Matrix((along, up, normal)).transposed().to_4x4()
        mat.translation = loc
        me.transform(mat)
        me.materials.append(M["reg"])
        ob = bpy.data.objects.new("Registration_" + ("R" if side > 0 else "L"), me)
        COLL.objects.link(ob)
        set_parent(ob, root)


# --- weathering (procedural textures) ---------------------------------------------

def C(h):
    return np.array(lin(h)[:3], np.float32)


BLUE, CREAM = C("#46738B"), C("#D8CCAE")
PRIMER, SILVER, METAL = C("#8E8E86"), C("#A6A69E"), C("#B4B4AE")
SOOT, OIL, MUD, GRIME = C("#24211E"), C("#3B2A18"), C("#6E5C43"), C("#5E5444")


def tape(coord, spacing, offset, width):
    """Rib/frame tape: (inside 0..1, dirt line at the edges) for lines every `spacing`."""
    d = np.abs((coord - offset + spacing / 2) % spacing - spacing / 2)
    inside = 1.0 - pt.smoothstep(d, width / 2 - 0.004, width / 2)
    edge = np.exp(-((d - width / 2) / 0.004) ** 2)
    return inside, edge


def stitches(along, across, pitch, width=0.003):
    """Small stitch marks along a tape centre line."""
    d = np.abs((along + pitch / 2) % pitch - pitch / 2)
    return ((d < 0.004) & (np.abs(across) < width)).astype(np.float32)


def patches(P, Nn, plist):
    """Fabric patches: (mask, stitch lines). plist: [(centre, axis a, axis b, half a, half b)]."""
    mask = np.zeros(len(P), np.float32)
    stitch = np.zeros(len(P), np.float32)
    for c, a, b, ha, hb in plist:
        c, a, b = (np.array(v, np.float32) for v in (c, a, b))
        n = np.cross(a, b)
        d = P - c
        da, db, dn = d @ a, d @ b, d @ n
        inside = (np.abs(da) < ha) & (np.abs(db) < hb) & (np.abs(dn) < 0.12) & (np.abs(Nn @ n) > 0.3)
        border = np.minimum(ha - np.abs(da), hb - np.abs(db))
        cross = np.abs(np.abs(da) / ha - np.abs(db) / hb) * min(ha, hb)
        line = ((border < 0.007) & ((np.sin((da + db) * 300) > 0))) | (cross < 0.003)
        mask = np.maximum(mask, inside.astype(np.float32))
        stitch = np.maximum(stitch, (inside & line).astype(np.float32))
    return mask, stitch


def weather_common(P, Nn, col, rough, metal, height, wear=1.0):
    """Sun fading, general grime, dirtier undersides, fabric grain, chips."""
    n = len(P)
    up = np.clip(Nn[:, 2], 0, 1)
    down = np.clip(-Nn[:, 2], 0, 1)
    fade = (0.10 + 0.25 * pt.fbm(P, 1.2, 3, seed=1) + 0.12 * up) * wear
    lum = col @ np.array([0.3, 0.59, 0.11], np.float32)
    faded = col * 0.75 + lum[:, None] * 0.25 + 0.05
    col = pt.mix(col, faded, fade)
    grime = (0.15 + 0.35 * pt.fbm(P, 2.5, 4, seed=2)) * wear + 0.20 * down
    grime += 0.25 * pt.smoothstep(pt.fbm(P, (5.0, 0.8, 9.0), 3, seed=14), 0.5, 0.8) * wear  # flow streaks
    col = pt.mix(col, col * np.array([0.62, 0.57, 0.48], np.float32), np.clip(grime, 0, 0.9) * 0.75)
    stains = pt.smoothstep(pt.fbm(P, 7.0, 4, seed=15), 0.58, 0.70) * wear
    col = pt.mix(col, col * np.array([0.70, 0.62, 0.50], np.float32), stains * 0.6)
    col *= (0.97 + 0.06 * pt.fbm(P, 220.0, 2, seed=3))[:, None]
    rough = np.clip(rough + 0.08 * pt.fbm(P, 8.0, 2, seed=4) - 0.04, 0, 1)
    return col, rough, metal, height


def chips(P, Nn, col, rough, metal, is_blue, threshold, under=None):
    c = pt.fbm(P, 70.0, 3, seed=5)
    front = np.clip(Nn[:, 1], 0, 1)
    m = pt.smoothstep(c, threshold - 0.10 * front, threshold - 0.10 * front + 0.02)
    under = under if under is not None else np.where(is_blue[:, None], PRIMER, CREAM * 0.8)
    return pt.mix(col, under, m), m


FUS_YS = np.array([r[0] for r in reversed(FUS)], np.float32)


def fus_col(i):
    return np.array([r[i] for r in reversed(FUS)], np.float32)


def rules_fuselage(P, Nn, part):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    zb, zt = np.interp(y, FUS_YS, fus_col(2)), np.interp(y, FUS_YS, fus_col(3))
    zs = zb + 0.45 * (zt - zb)
    blue = (z < zs) | ((z >= zs + 0.025) & (z < zs + 0.045))
    col = np.where(blue[:, None], BLUE, CREAM).astype(np.float32)
    cowl = y > 1.0
    rough = np.where(cowl, 0.55, 0.82).astype(np.float32)
    metal = np.zeros(len(P), np.float32)
    height = np.zeros(len(P), np.float32)
    col, rough, metal, height = weather_common(P, Nn, col, rough, metal, height)

    # Fabric over the frames behind the cabin; panel seams and rivets on the cowl.
    fr_in, fr_edge = tape(y, 0.47, -1.25, 0.03)
    fr = (y < -1.05)
    height += np.where(fr, fr_in * 0.6, 0)
    col = pt.mix(col, col * 0.78, np.where(fr, fr_edge * 0.5, 0))
    seam = np.exp(-((y - 1.0) / 0.003) ** 2) + np.exp(-((y - 1.40) / 0.003) ** 2) * cowl
    seam += np.exp(-((z - zs) / 0.003) ** 2) * cowl
    col = pt.mix(col, col * 0.35, np.clip(seam, 0, 1) * 0.8)
    rivet_row = (np.abs(y - 1.0) < 0.012) | ((np.abs(y - 1.40) < 0.012) & cowl)
    rv = ((np.abs((z + 0.0175) % 0.035 - 0.0175) < 0.004) & rivet_row).astype(np.float32)
    height += rv * 0.3
    col = pt.mix(col, col * 0.7, rv * 0.35)

    col, chip = chips(P, Nn, col, rough, metal, blue, np.where(cowl, 0.80, 0.86),
                      np.where(cowl[:, None], METAL, np.where(blue[:, None], PRIMER, CREAM * 0.8)))
    metal = np.where(cowl, chip * 0.9, metal)
    rough = np.where(cowl, rough - chip * 0.2, rough)

    # Exhaust soot streaming aft along both sides from the stacks.
    d = np.clip(0.92 - y, 0, None)
    zc = -0.72 - 0.06 * d
    w = 0.05 + 0.07 * d
    streak = 0.6 + 0.4 * pt.fbm(P, (2.0, 1.5, 30.0), 3, seed=6)
    soot = np.exp(-((z - zc) / w) ** 2) * np.exp(-d / 2.4) * streak * (y < 0.95) * (np.abs(x) > 0.05)
    col = pt.mix(col, SOOT, np.clip(soot * 1.4, 0, 0.9))
    rough = np.clip(rough + soot * 0.1, 0, 1)

    # Oil: streaks running aft along the belly, drips down the cowl sides.
    belly = pt.smoothstep(pt.fbm(P, (8.0, 1.0, 40.0), 3, seed=7), 0.52, 0.72)
    belly *= np.exp(-np.clip(1.65 - y, 0, None) / 1.3) * (z < zb + 0.18) * (y < 1.65)
    drips = pt.smoothstep(pt.fbm(P, (10.0, 45.0, 1.5), 3, seed=8), 0.55, 0.75)
    drips *= ((y > 1.05) & (y < 1.62) & (z < -0.48)).astype(np.float32)
    oil = np.clip(belly + drips * 0.9, 0, 0.9)
    col = pt.mix(col, OIL, oil)
    rough = np.clip(rough - oil * 0.35, 0.15, 1)

    # Mud thrown up by the wheels.
    spat = pt.smoothstep(pt.fbm(P, 60.0, 2, seed=9), 0.66, 0.72)
    spat *= ((y < 0.45) & (y > -1.8) & (z < zb + 0.25)).astype(np.float32)
    col = pt.mix(col, MUD, spat * 0.6)

    side = lambda sx, yc, zc_, ha, hb: ((sx * 0.33, yc, zc_), (0, 1, 0), (0, 0, 1), ha, hb)
    pm, ps = patches(P, Nn, [side(-1, -0.42, -0.87, 0.075, 0.06), side(1, -2.9, -0.50, 0.10, 0.07),
                             side(-1, -3.25, -0.52, 0.11, 0.08), side(1, 0.62, -0.86, 0.06, 0.05)])
    col = pt.mix(col, SILVER * (0.9 + 0.1 * pt.fbm(P, 30, 1, seed=10))[:, None], pm * 0.85)
    col = pt.mix(col, col * 0.4, ps)
    height += pm * 0.4
    return col, rough, metal, height


def wing_surface_common(P, Nn, s, rib_sp, rib_off, tip, along):
    """Paint, ribs and stitching for a fabric flying surface. s: spanwise, along: chordwise coordinate."""
    col = np.where(tip[:, None], BLUE, CREAM).astype(np.float32)
    rough = np.full(len(P), 0.82, np.float32)
    metal = np.zeros(len(P), np.float32)
    height = np.zeros(len(P), np.float32)
    col, rough, metal, height = weather_common(P, Nn, col, rough, metal, height)
    rin, redge = tape(s, rib_sp, rib_off, 0.04)
    near, _ = tape(s, rib_sp, rib_off, 0.10)
    height += rin * 0.7
    dirt = pt.fbm(P, (3.0, 12.0, 3.0), 3, seed=16)
    col = pt.mix(col, col * 0.72, redge * 0.7 + (near - rin) * 0.25 * dirt)
    centre = (s - rib_off + rib_sp / 2) % rib_sp - rib_sp / 2
    st = stitches(along, centre, 0.055)
    col = pt.mix(col, col * 0.55, st * 0.7)
    height += st * 0.3
    col, _ = chips(P, Nn, col, rough, metal, tip, 0.86)
    return col, rough, metal, height


def rules_wing(P, Nn, part):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    s = np.abs(x)
    col, rough, metal, height = wing_surface_common(P, Nn, s, 0.31, 0.22, s > 4.85, y)
    # Trailing-edge tape and grime around the wing root and strut fittings.
    te = np.exp(-((y - (WING_TE + 0.02)) / 0.012) ** 2) * (part == 2)
    height += te * 0.5
    root = np.exp(-(s / 0.30) ** 2) * 0.6
    fit = np.exp(-((s - 2.10) ** 2 + (y - 0.16) ** 2) / 0.01) + np.exp(-((s - 2.10) ** 2 + (y + 0.64) ** 2) / 0.01)
    dirt = np.clip(root * 0.6 + fit * 0.5, 0, 0.7) * pt.smoothstep(pt.fbm(P, 30.0, 3, seed=12), 0.35, 0.65)
    col = pt.mix(col, col * 0.45, dirt)
    top = lambda sx, sc, yc, h: ((sx * sc, yc, 0.14 + sc * math.tan(DIH)), (1, 0, 0), (0, 1, 0), h, h)
    pm, ps = patches(P, Nn, [top(1, 1.25, 0.02, 0.11), top(-1, 3.95, -0.25, 0.10), top(-1, 2.15, -0.55, 0.12),
                             top(1, 3.6, -0.45, 0.08)])
    col = pt.mix(col, SILVER * (0.9 + 0.1 * pt.fbm(P, 30, 1, seed=13))[:, None], pm * 0.85)
    col = pt.mix(col, col * 0.4, ps)
    height += pm * 0.4
    return col, rough, metal, height


def rules_tail(P, Nn, part):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    horiz = (part == 4) | (part == 5)
    # Stabilizer and elevator: ribs across the span, blue tips. Fin and rudder:
    # horizontal ribs, blue lower-aft triangle.
    a = np.array([-3.70, FIN_Z0 - 0.05], np.float32)
    b = np.array([-5.05, FIN_Z0 + 0.62], np.float32)
    dvec = (b - a) / np.linalg.norm(b - a)
    nrm = np.array([-dvec[1], dvec[0]], np.float32)
    if nrm[1] < 0:
        nrm = -nrm
    below = ((np.stack([y, z], 1) - a) @ nrm) < 0
    s = np.where(horiz, np.abs(x), z - FIN_Z0)
    tip = np.where(horiz, np.abs(x) > 1.22, below)
    col, rough, metal, height = wing_surface_common(P, Nn, s, 0.21, 0.12, tip, y)
    pm, ps = patches(P, Nn, [((0.85, -4.42, STAB_Z + 0.03), (1, 0, 0), (0, 1, 0), 0.07, 0.07),
                             ((-0.03, -4.25, FIN_Z0 + 0.35), (0, 1, 0), (0, 0, 1), 0.06, 0.05)])
    col = pt.mix(col, SILVER[None, :] * np.ones_like(col), pm * 0.8)
    col = pt.mix(col, col * 0.4, ps)
    return col, rough, metal, height


def paint_all():
    os.makedirs(TEX_DIR, exist_ok=True)
    O = bpy.data.objects
    jobs = [
        ("fus", [(O["Fuselage"], 1, {"Cub_Fus"})], rules_fuselage),
        ("wing", [(O["Wing"], 2, {"Cub_Wing"}), (O["Aileron_L"], 3, None), (O["Aileron_R"], 3, None)], rules_wing),
        ("tail", [(O["Stabilizer"], 4, {"Cub_Tail"}), (O["Elevator"], 5, {"Cub_Tail"}),
                  (O["Fin"], 6, {"Cub_Tail"}), (O["Rudder"], 7, {"Cub_Tail"})], rules_tail),
    ]
    for key, items, rules in jobs:
        img = IMGS[key]["base"]
        W, H = img.size
        texels = pt.paint(items, W, H, rules, IMGS[key], TEX_DIR, normal_strength=3.0 * QUALITY)
        print("painted", key, W, "x", H, texels, "texels")

# --- main --------------------------------------------------------------------

def build():
    global COLL
    for name in ("Cube",):
        if name in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[name])
    COLL = bpy.data.collections.get("Cub")
    if COLL:
        for o in list(COLL.objects):
            bpy.data.objects.remove(o)
    else:
        COLL = bpy.data.collections.new("Cub")
        bpy.context.scene.collection.children.link(COLL)
    for me in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(me)
    make_materials()
    root = empty("Cub", (0, 0, 0))
    build_fuselage(root)
    build_wing(root)
    build_tail(root)
    build_struts(root)
    build_gear(root)
    build_controls(root)
    build_details(root)
    build_engine(root)
    build_prop(root)
    build_registration(root)
    bpy.context.view_layer.update()
    if globals().get("PAINT", True):
        paint_all()
    return root


def export():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    lc = bpy.context.view_layer.layer_collection.children["Cub"]
    bpy.context.view_layer.active_layer_collection = lc
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_active_collection=True,
                              export_yup=True, export_apply=True, export_cameras=False, export_lights=False,
                              export_image_format="WEBP", export_image_quality=90)
    print("exported", OUT, os.path.getsize(OUT), "bytes")


root = build()
faces = sum(len(o.data.polygons) for o in COLL.objects if o.type == "MESH")
print("objects", len(COLL.objects), "faces", faces)
if globals().get("EXPORT", True):
    export()
