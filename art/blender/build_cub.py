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
TEX = {"fus": (2048, 1024), "wing": (4096, 1024), "tail": (2048, 1024), "int": (1024, 512), "cab": (2048, 2048),
       "pnl": (1024, 1024), "frm": (2048, 1024), "seat": (1024, 1024)}
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
    M["engine"] = material("Engine_Black", "#1C1B1A", 0.45, 0.7)
    M["exhaust"] = material("Exhaust_Rust", "#5A3420", 0.7, 0.5)
    M["steel"] = material("Steel", "#8C8C8C", 0.45, 1.0)
    M["tyre"] = material("Tyre", "#141414", 0.92)
    M["prop"] = material("Prop_Black", "#151515", 0.5)
    M["tip"] = material("Prop_Tip", "#E8B830", 0.5)
    M["disc"] = material("Prop_Disc", "#202020", 0.5, alpha=0.08, double=True)
    M["reg"] = material("Registration", "#E2DAC2", 0.7, double=True)
    M["frame"] = material("Frame_Tube", "#5E7884", 0.6, 0.3)
    M["cowl_edge"] = material("Cowl_Edge", "#B9B09A", 0.5, 0.6)
    M["cavity"] = material("Engine_Cavity", "#141210", 0.9)
    M["leather"] = material("Seat_Leather", "#262C33", 0.55)
    M["wood"] = material("Floor_Wood", "#4E3D2B", 0.85)
    M["belt"] = material("Seat_Belt", "#5E5B45", 0.9)
    M["map"] = material("Paper_Map", "#BFCDC4", 0.85)
    M["brass"] = material("Brass", "#A88A4C", 0.35, 1.0)
    M["pedal"] = material("Pedal_Metal", "#5E584C", 0.55, 0.7)
    M["panel"] = material("Panel_Paint", "#39423D", 0.6, 0.3)
    M["placard"] = material("Placard", "#9A968A", 0.4, 0.8)
    M["bezel"] = material("Bezel", "#1F1E1B", 0.45, 0.6)
    M["tank"] = material("Fuel_Tank", "#5C5F57", 0.6, 0.5)
    M["blue"] = material("Paint_Blue", "#557A8C", 0.7)
    for key, (w, h) in TEX.items():
        M["tex_" + key], IMGS[key] = pt.textured_material("Cub_" + key.capitalize(),
                                                         int(w * QUALITY), int(h * QUALITY))

# --- mesh building -------------------------------------------------------------

class MB:
    """Vertices + faces with a material key per face."""
    def __init__(self):
        self.v, self.f, self.m, self.uv, self.tag = [], [], [], [], []

    def vert(self, p, uv=(0.0, 0.0)):
        self.v.append(tuple(p))
        self.uv.append(tuple(uv))
        return len(self.v) - 1

    def face(self, idx, mat, tag=-1):
        self.f.append(list(idx))
        self.m.append(mat)
        self.tag.append(tag)

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


SOLID = []  # (object name, thickness): given real panel thickness after painting


def apply_solidify():
    for name, t in SOLID:
        me = bpy.data.objects[name].data
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=t)
        bm.to_mesh(me)
        bm.free()


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


def lathe(mb, profile, mat, axis_pt, axis="x", sides=16, sign=1.0, open_ends=False):
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
    mb.loft(rings, mf, cap0=tip0 is None and not open_ends, cap1=tip1 is None and not open_ends)
    for tip, rg in ((tip0, rings[0]), (tip1, rings[-1])):
        if tip is not None:
            for k in range(sides):
                mb.face((rg[k], rg[(k + 1) % sides], tip), mf(0, 0))

# --- fuselage ----------------------------------------------------------------

# y, width, z bottom, z top, [window bottom, window top]
FUS = [
    (1.735, 0.14, -0.70, -0.55),
    (1.71, 0.26, -0.76, -0.48),
    (1.66, 0.38, -0.83, -0.41),
    (1.57, 0.50, -0.91, -0.33),
    (1.42, 0.60, -0.98, -0.275),
    (1.20, 0.68, -1.03, -0.24),
    (1.00, 0.72, -1.06, -0.22, -0.27, -0.245),
    (0.80, 0.72, -1.08, -0.15, -0.36, -0.17),
    (0.42, 0.72, -1.10, -0.015, -0.52, -0.07),
    (0.00, 0.72, -1.10, -0.015, -0.52, -0.065),
    (-0.95, 0.71, -1.07, -0.02, -0.52, -0.07),
    (-1.20, 0.69, -1.05, -0.03),
    (-1.60, 0.63, -1.01, -0.10),
    (-2.50, 0.48, -0.93, -0.28),
    (-3.50, 0.29, -0.84, -0.46),
    (-4.30, 0.14, -0.73, -0.565),
    (-4.62, 0.035, -0.665, -0.60),
]
FUS_SIDE = 0.36  # cabin half-width: struts, gear and door fittings sit on it
FUS = [r if len(r) == 6 else r + (r[2] + 0.70 * (r[3] - r[2]), r[2] + 0.90 * (r[3] - r[2])) for r in FUS]
EXTRA_Y = [0.97, 0.90, 0.70, 0.60, 0.50, 0.40, 0.36, 0.20, -0.15, -0.30, -0.34, -0.60,
           -2.0, -3.0, -3.9, 1.05, 1.10, 1.15, 1.25, 1.30, 1.35, 1.48, 1.62, 1.69, 1.725]
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
    # The windshield bulges forward and the cowling rounds off into a barrel towards the
    # nose bowl: the upper half starts rounding at the wing leading edge, the lower at the firewall.
    r_low = 0.0 if y <= 1.0 else min(1.0, (y - 1.0) / 0.55) ** 0.8
    t = min(1.0, max(0.0, (y - 0.42) / 0.58))
    r_up = 0.55 * t * t * (3 - 2 * t) if y <= 1.0 else 0.55 + 0.45 * r_low
    if r_up > 0:
        a, b, zc, n = 0.5 * w, 0.5 * h, 0.5 * (zb + zt), 2.6
        rnd = []
        for px, pz in right:  # same direction from the centre as the box point: no twisting
            t = math.atan2((pz - zc) / b, px / a)
            c, s_ = math.cos(t), math.sin(t)
            rnd.append((a * abs(c) ** (2 / n), zc + b * math.copysign(abs(s_) ** (2 / n), s_)))
        zc = 0.5 * (zb + zt)
        right = [(lerp(p[0], q[0], r_up if p[1] > zc else r_low), lerp(p[1], q[1], r_up if p[1] > zc else r_low))
                 for p, q in zip(right, rnd)]
    ring = right + [(-x, z) for x, z in reversed(right[1:-1])]
    return [Vector((x, y, z)) for x, z in ring]


def surface_x(y, z):
    """Half-width of the fuselage skin at station y and height z."""
    right = [p for p in section(y) if p.x >= 0][:11]
    right.sort(key=lambda p: p.z)
    for a, b in zip(right, right[1:]):
        if a.z <= z <= b.z and b.z > a.z:
            return lerp(a.x, b.x, (z - a.z) / (b.z - a.z))
    return max(p.x for p in right)


def _rear_window():
    pts = [(-0.12, -0.50), (-0.12, -0.075), (-0.93, -0.075)]
    for a in range(15, 91, 15):  # rear edge sweeps down and forward
        t = math.radians(a)
        pts.append((-0.62 - 0.31 * math.cos(t), -0.075 - 0.425 * math.sin(t)))
    return pts


# Side window outlines (y, z), same on both sides; the right front one is the door window.
WINDOWS = [[(0.36, -0.50), (0.39, -0.075), (-0.07, -0.075), (-0.07, -0.50)], _rear_window()]


def inside(poly, y, z):
    hit = False
    for (y1, z1), (y2, z2) in zip(poly, poly[1:] + poly[:1]):
        if (z1 > z) != (z2 > z) and y < y1 + (z - z1) * (y2 - y1) / (z2 - z1):
            hit = not hit
    return hit


def cut_windows(mb):
    """Cut the window outlines into the cabin sides and glaze them (exact shapes, not grid steps)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    tagl = bm.faces.layers.int.new("band")
    keys = list(dict.fromkeys(mb.m + ["glass"]))
    verts = [bm.verts.new(v) for v in mb.v]
    for idx, m, tg in zip(mb.f, mb.m, mb.tag):
        f = bm.faces.new([verts[i] for i in idx])
        f.material_index = keys.index(m)
        f[tagl] = tg
        for lp in f.loops:
            lp[uvl].uv = mb.uv[idx[[verts[i] for i in idx].index(lp.vert)]]
    for side in (1, -1):
        for poly in WINDOWS:
            ys, zs = [p[0] for p in poly], [p[1] for p in poly]
            for (y1, z1), (y2, z2) in zip(poly, poly[1:] + poly[:1]):
                geom = []
                for f in bm.faces:
                    c = f.calc_center_median()
                    if side * c.x > 0.2 and min(ys) - 0.06 < c.y < max(ys) + 0.06 and min(zs) - 0.06 < c.z < max(zs) + 0.06:
                        geom.append(f)
                if not geom:
                    continue
                edges = {e for f in geom for e in f.edges}
                vs = {v for f in geom for v in f.verts}
                no = Vector((0, -(z2 - z1), y2 - y1)).normalized()
                bmesh.ops.bisect_plane(bm, geom=list(vs) + list(edges) + geom, plane_co=Vector((0, y1, z1)), plane_no=no)
        bm.normal_update()
        for f in bm.faces:
            c = f.calc_center_median()
            if side * c.x > 0.2 and abs(f.normal.x) > 0.5 and any(inside(poly, c.y, c.z) for poly in WINDOWS):
                f.material_index = keys.index("glass")
    out = MB()
    bm.verts.index_update()
    uv_of = {}
    for f in bm.faces:
        for lp in f.loops:
            uv_of.setdefault(lp.vert.index, tuple(lp[uvl].uv))
    for v in bm.verts:
        out.vert(v.co, uv_of.get(v.index, (0.0, 0.0)))
    for f in bm.faces:
        out.face([v.index for v in f.verts], keys[f.material_index], f[tagl])
    bm.free()
    return out


# Cylinder openings in the cowl sides: (centre y, centre z, half length, half height) per side.
CYL_OPEN = {1: (1.43, -0.50, 0.17, 0.11), -1: (1.47, -0.50, 0.17, 0.11)}


def band_of(j, n_right=11):
    return j if j < n_right - 1 else 2 * (n_right - 1) - 1 - j


def windshield(y):
    return 0.42 < y < 0.97


def side_window(y):
    return -0.95 < y < 0.36 and not (-0.34 < y < -0.30)


def fus_material(y, band):
    if band == 6:
        return "glass" if windshield(y) else "tex_fus"
    if band >= 7:
        return "glass" if windshield(y) else "tex_fus"
    return "tex_fus"


FUS_Y0, FUS_LEN = 1.745, 6.365


def fus_uv_ring(pts, y):
    """Closed section + repeated first point; u along the fuselage, v around it."""
    ring = pts + [pts[0]]
    arc = [0.0]
    for a, b in zip(ring, ring[1:]):
        arc.append(arc[-1] + (b - a).length)
    u = 0.01 + 0.98 * (FUS_Y0 - y) / FUS_LEN
    return ring, [(u, 0.01 + 0.98 * a / arc[-1]) for a in arc]


def fus_part(c, n, mat, band):
    """Which real panel a fuselage face belongs to (band: row of the section it came from)."""
    y, x, z = c.y, c.x, c.z
    w, zb, zt, zwb, zwt = fus_at(y)
    side = "R" if x > 0 else "L"
    if mat == "glass":
        if y > 0.40:
            return "Windshield"
        if y > -0.10:
            return "Door_window_R" if side == "R" else "Window_L_front"
        return f"Window_{side}_rear"
    if y > 1.62:
        return "Nose_bowl"
    if y > 1.0:
        if band >= 8:
            return "Cowl_top_" + side
        if band <= 2:
            return "Cowl_bottom"
        return "Cowl_side_" + side
    if band == 0:
        return "Belly"
    if side == "R" and -0.07 < y < 0.37 and (2 <= band <= 5 or (band == 6 and z < -0.50)):
        return "Door_lower_R"
    if y < -4.40:
        return "Tail_cone"
    if band >= 8:
        if -0.42 < y < 0.42:
            return None  # open to the skylight in the wing centre section
        return "Turtle_deck" if y < -0.95 else "Cabin_roof"
    return "Skin_" + side


def split_parts(mb):
    groups = {}
    for fi, face in enumerate(mb.f):
        pts = [Vector(mb.v[i]) for i in face]
        c = sum(pts, Vector()) / len(pts)
        n = Vector()
        for a, b in zip(pts, pts[1:] + pts[:1]):
            n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        if n.length:
            n.normalize()  # loft faces wind outward
        groups.setdefault(fus_part(c, n, mb.m[fi], mb.tag[fi]), []).append(fi)
    out = {}
    for name, faces in groups.items():
        sub, remap = MB(), {}
        for fi in faces:
            idx = []
            for vi in mb.f[fi]:
                if vi not in remap:
                    remap[vi] = sub.vert(mb.v[vi], mb.uv[vi])
                idx.append(remap[vi])
            sub.face(idx, mb.m[fi])
        out[name] = sub
    return out


def build_glazing_frames(parent):
    """Aluminium frames round the side windows and the windshield edges."""
    mb = MB()
    for side in (1, -1):
        for poly in WINDOWS:
            pts = [Vector((side * (surface_x(y, z) + 0.004), y, z)) for y, z in poly + poly[:1]]
            tube(mb, pts, 0.007, "cowl_edge", 6, cap=False)
        post = [Vector((side * (surface_x(0.41, z) + 0.004), 0.41, z)) for z in (-0.50, -0.30, -0.10, -0.02)]
        tube(mb, post, 0.008, "cowl_edge", 6)
    base = [p + Vector((0, 0, 0.004)) for p in section(0.965) if p.z > fus_at(0.965)[3] - 0.01]
    base.sort(key=lambda p: p.x)
    tube(mb, base, 0.008, "cowl_edge", 6)
    obj("Window_frames", mb, parent, smooth=60)


def cushion(mb, c, sx, sy, sz, mat, r=0.03):
    """Upholstered pad: a rounded-rectangle block, slightly puffed in the middle."""
    c = Vector(c)

    def rr(scale, z):
        hx, hy = sx / 2 * scale - r, sy / 2 * scale - r
        pts = []
        for cx, cy, a0 in ((hx, hy, 0), (-hx, hy, 90), (-hx, -hy, 180), (hx, -hy, 270)):
            for a in (0, 30, 60, 90):
                t = math.radians(a0 + a)
                pts.append(c + Vector((cx + r * math.cos(t), cy + r * math.sin(t), z)))
        return mb.ring(pts)
    rings = [rr(0.94, -sz / 2), rr(1.0, -sz / 4), rr(1.02, 0), rr(1.0, sz / 4), rr(0.92, sz / 2)]
    mb.loft(rings, mat, cap0=True, cap1=True)


def seat(mb, y_front, y_back, z_top, back_top, width, name):
    """Tube-frame seat: pan cushion, tilted back cushion, legs to the floor, lap belt."""
    zf = FLOOR_Z
    yc = 0.5 * (y_front + y_back)
    cushion(mb, (0, yc, z_top - 0.04), width, y_front - y_back, 0.08, "leather")
    # Back cushion: built upright, then tilted back about its bottom edge.
    bm = MB()
    h = back_top - z_top
    cushion(bm, (0, 0, h / 2), width - 0.02, 0.07, h, "leather")
    tilt = Matrix.Rotation(math.radians(-12), 4, "X")
    for v in bm.v:
        q = tilt @ Vector(v) + Vector((0, y_back - 0.03, z_top))
        mb.vert(q)
    off = len(mb.v) - len(bm.v)
    for f, m in zip(bm.f, bm.m):
        mb.face([i + off for i in f], m)
    hw = width / 2 - 0.02
    for sx in (-1, 1):
        for yy in (y_front - 0.03, y_back + 0.03):
            tube(mb, [(sx * hw, yy, z_top - 0.08), (sx * hw, yy, zf)], 0.011, "frame", 6)
        tube(mb, [(sx * hw, y_front - 0.03, z_top - 0.09), (sx * hw, y_back + 0.03, z_top - 0.09)], 0.011, "frame", 6)
        tube(mb, [(sx * hw, y_front - 0.03, zf + 0.02), (sx * hw, y_back + 0.03, z_top - 0.09)], 0.008, "frame", 6)
        # Lap belt halves draped over the pan, buckle in the middle.
        tube(mb, [(sx * (hw + 0.01), y_back + 0.06, z_top - 0.07), (sx * (hw - 0.02), y_back + 0.10, z_top + 0.01),
                  (sx * 0.06, yc, z_top + 0.012)], 0.022, "belt", 6, squash=0.15)
    box(mb, (0, yc, z_top + 0.015), (0.07, 0.05, 0.012), "steel")
    # Back frame: two uprights behind the cushion, a top bar, hinge brackets.
    tb = Matrix.Rotation(math.radians(-12), 4, "X")
    for sx in (-1, 1):
        lo = Vector((sx * (hw - 0.01), y_back - 0.07, z_top - 0.02))
        hi = tb @ Vector((sx * (hw - 0.01), -0.04, back_top - z_top)) + Vector((0, y_back - 0.03, z_top))
        tube(mb, [lo, hi], 0.009, "frame", 6)
        box(mb, lo + Vector((0, 0.01, -0.02)), (0.02, 0.03, 0.03), "steel")
    tube(mb, [tb @ Vector((-(hw - 0.01), -0.04, back_top - z_top)) + Vector((0, y_back - 0.03, z_top)),
              tb @ Vector((hw - 0.01, -0.04, back_top - z_top)) + Vector((0, y_back - 0.03, z_top))], 0.009, "frame", 6)


FLOOR_Z = -1.045


def build_cabin(root):
    """Inside the cabin. Moving controls get pivot nodes (animated by the game later)."""
    cab = empty("Cabin", (0, 0, 0), parent=root)
    mb = MB()
    # Floorboards: planks running fore and aft either side of a metal centre strip.
    for k in range(-2, 3):
        if k == 0:
            box(mb, (0, -0.10, FLOOR_Z - 0.004), (0.07, 1.42, 0.006), "pedal")
            continue
        xc = math.copysign(0.035 + 0.055 + (abs(k) - 1) * 0.112, k)
        box(mb, (xc, -0.10, FLOOR_Z - 0.008), (0.106, 1.42, 0.014), "wood")
    # Control cables and pulleys along the floor, both sides.
    for sx in (-1, 1):
        x = sx * 0.27
        tube(mb, [(x, 0.70, FLOOR_Z + 0.03), (x, -0.62, FLOOR_Z + 0.03), (sx * 0.12, -1.6, -0.95)], 0.0025, "steel", 4)
        for yy in (0.10, -0.62):
            lathe(mb, [(-0.006, 0), (-0.006, 0.022), (0.006, 0.022), (0.006, 0)], "steel",
                  (x, yy, FLOOR_Z + 0.035), "x", 10)
    for args, name in (((-0.40, -0.78, -0.88, -0.42, 0.50), "Seat_rear"), ((0.38, 0.03, -0.90, -0.58, 0.48), "Seat_front")):
        sm = MB()
        seat(sm, *args, name)
        obj(name, sm, cab, smooth=45)
    # Map pocket on the left wall with a folded chart, and a handheld radio on the frame.
    wx = -(FUS_SIDE - 0.035)
    box(mb, (wx, -0.27, -0.76), (0.012, 0.28, 0.16), "belt")
    box(mb, (wx + 0.012, -0.24, -0.66), (0.004, 0.22, 0.14), "map")
    box(mb, (wx + 0.02, -0.72, -0.40), (0.035, 0.06, 0.13), "engine")
    tube(mb, [(wx + 0.02, -0.71, -0.33), (wx + 0.02, -0.71, -0.20)], 0.004, "engine", 5)
    # Overhead: brass fuel line from the wing tanks and the cross tube carrying the trim crank.
    tube(mb, [(-FUS_SIDE + 0.03, 0.05, -0.035), (FUS_SIDE - 0.03, 0.05, -0.035)], 0.007, "brass", 8)
    tube(mb, [(0, 0.05, -0.035), (0, 0.05, -0.09)], 0.008, "brass", 8)
    tube(mb, [(-FUS_SIDE + 0.03, -0.25, -0.045), (FUS_SIDE - 0.03, -0.25, -0.045)], 0.011, "frame", 6)
    # Door latches and hinges (right side).
    box(mb, (FUS_SIDE - 0.025, -0.05, -0.62), (0.02, 0.08, 0.03), "steel")
    box(mb, (FUS_SIDE - 0.035, -0.05, -0.62), (0.03, 0.02, 0.02), "pedal")
    for yy in (0.25, -0.02):
        lathe(mb, [(-0.02, 0), (-0.02, 0.008), (0.02, 0.008), (0.02, 0)], "steel",
              (FUS_SIDE - 0.01, yy, -0.99), "y", 6)
    obj("Cabin_fixed", mb, cab, smooth=45)

    # Sticks (pivot at the floor; the game will tilt them with the controls): bolted base
    # plate, ribbed rubber boot, black tube with a slight bend, ribbed rubber grip.
    for name, y, top in (("Stick_rear", -0.12, -0.52), ("Stick_front", 0.44, -0.56)):
        piv = empty(name, (0, y, FLOOR_Z), parent=cab)
        m = MB()
        base = Vector((0, y, FLOOR_Z))
        lathe(m, [(0, 0), (0, 0.055), (0.004, 0.055), (0.006, 0)], "steel", base, "z", 20)
        for k in range(6):
            a = k * math.pi / 3
            lathe(m, [(0, 0), (0, 0.005), (0.004, 0.004), (0.005, 0)], "steel",
                  base + Vector((0.045 * math.cos(a), 0.045 * math.sin(a), 0.004)), "z", 6)
        boot = []
        for k in range(9):
            h = 0.006 + k * 0.011
            boot.append((h, (0.04 - h * 0.25) * (1.0 if k % 2 == 0 else 0.88)))
        lathe(m, [(0.006, 0)] + boot + [(0.1, 0)], "tyre", base, "z", 16)
        shaft = [base + Vector((0, 0, 0.09)), Vector((0, y + 0.012, top - 0.14)), Vector((0, y - 0.004, top - 0.11))]
        tube(m, shaft, 0.011, "engine", 10)
        grip = []
        for k in range(12):
            grip.append((k * 0.009, 0.0165 if k % 2 == 0 else 0.0185))
        lathe(m, [(0, 0)] + grip + [(0.105, 0.016), (0.11, 0.009), (0.112, 0)], "tyre",
              Vector((0, y - 0.004, top - 0.11)), "z", 14)
        obj(name + "_mesh", m, piv, smooth=45)
    # Rudder pedals with heel brakes behind them (rear set) and the front set under the panel.
    for name, y, heel in (("Pedals_rear", 0.16, True), ("Pedals_front", 0.66, False)):
        piv = empty(name, (0, y, FLOOR_Z + 0.03), parent=cab)
        m = MB()
        tube(m, [(-0.16, y, FLOOR_Z + 0.03), (0.16, y, FLOOR_Z + 0.03)], 0.010, "pedal", 8)
        for sx in (-1, 1):
            tube(m, [(sx * 0.11, y, FLOOR_Z + 0.03), (sx * 0.11, y + 0.015, FLOOR_Z + 0.13)], 0.008, "pedal", 6)
            box(m, (sx * 0.11, y + 0.02, FLOOR_Z + 0.15), (0.075, 0.012, 0.10), "pedal")
            for k in range(5):
                box(m, (sx * 0.11, y + 0.027, FLOOR_Z + 0.115 + k * 0.017), (0.068, 0.004, 0.004), "engine")
        obj(name + "_mesh", m, piv, smooth=45)
        if heel:
            for sx, tag in ((-1, "L"), (1, "R")):
                hp = empty(f"HeelBrake_{tag}", (sx * 0.16, y - 0.10, FLOOR_Z + 0.01), parent=cab)
                hm = MB()
                box(hm, (sx * 0.16, y - 0.12, FLOOR_Z + 0.035), (0.06, 0.06, 0.008), "pedal")
                tube(hm, [(sx * 0.16, y - 0.10, FLOOR_Z + 0.01), (sx * 0.16, y - 0.12, FLOOR_Z + 0.03)], 0.006, "pedal", 6)
                obj(f"HeelBrake_{tag}_mesh", hm, hp, smooth=45)
    # Throttles on the left wall, rear and front: slotted quadrant housing with a friction
    # knob, flat lever arm with a black ball, joined by a push rod.
    for name, y in (("Throttle_rear", -0.32), ("Throttle_front", 0.30)):
        base = Vector((wx + 0.018, y, -0.70))
        q = MB()
        box(q, base + Vector((-0.004, 0, -0.005)), (0.022, 0.11, 0.075), "engine")
        box(q, base + Vector((0.008, 0, 0.012)), (0.004, 0.09, 0.012), "steel")  # slot plate
        for sy in (-1, 1):
            lathe(q, [(0, 0), (0, 0.004), (0.003, 0.003), (0.004, 0)], "steel",
                  base + Vector((0.008, sy * 0.045, -0.03)), "x", 6)
        lathe(q, [(0, 0), (0, 0.009), (0.008, 0.009), (0.01, 0.006), (0.012, 0)], "engine",
              base + Vector((0.008, 0.035, -0.022)), "x", 12)  # friction knob
        obj(name + "_quadrant", q, cab, smooth=30)
        piv = empty(name, tuple(base + Vector((0.01, 0, -0.01))), parent=cab)
        m = MB()
        tube(m, [base + Vector((0.012, 0, -0.01)), base + Vector((0.02, -0.01, 0.06)), base + Vector((0.024, -0.02, 0.11))],
             0.006, "steel", 6, squash=0.4, flat_axis=(1, 0, 0))
        knob = base + Vector((0.026, -0.022, 0.125))
        lathe(m, [(-0.018, 0)] + [(0.018 * math.sin(t), 0.018 * math.cos(t)) for t in
                                   [math.radians(a) for a in range(-80, 81, 20)]] + [(0.018, 0)], "engine", knob, "z", 14)
        obj(name + "_lever", m, piv, smooth=50)
    rod = MB()
    tube(rod, [(wx + 0.02, -0.32, -0.72), (wx + 0.02, 0.30, -0.72)], 0.004, "steel", 5)
    obj("Throttle_rod", rod, cab, smooth=45)
    # Trim crank on the overhead cross tube.
    piv = empty("Trim_crank", (0, -0.25, -0.06), parent=cab)
    m = MB()
    lathe(m, [(0, 0), (0, 0.022), (0.02, 0.022), (0.02, 0)], "steel", (0, -0.25, -0.06), "z", 10, -1)
    tube(m, [(0, -0.25, -0.075), (0.08, -0.25, -0.085)], 0.007, "steel", 6)
    lathe(m, [(0, 0), (0, 0.012), (0.05, 0.012), (0.05, 0)], "engine", (0.08, -0.25, -0.085), "z", 8, -1)
    obj("Trim_crank_mesh", m, piv, smooth=45)
    build_panel(cab)
    build_cabin_details(cab)


def strip(mb, a, b, normal, width=0.018, pitch=0.032):
    """Riveted aluminium strip lying on a wall from a to b (the fabric is laced to the tubes
    under these), with dome rivets every `pitch`."""
    a, b, nrm = Vector(a), Vector(b), Vector(normal).normalized()
    d = (b - a)
    L = d.length
    d.normalize()
    side = nrm.cross(d).normalized() * (width / 2)
    t = nrm * 0.0018
    pts = [a - side, a + side, b + side, b - side]
    lo = [mb.vert(p) for p in pts]
    hi = [mb.vert(p + t) for p in pts]
    mb.face(hi, "cowl_edge")
    for k in range(4):
        mb.face((lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k]), "cowl_edge")
    n = max(2, int(L / pitch))
    for k in range(n + 1):
        c = a + d * (L * k / n) + t
        verts = [mb.vert(c + (side.normalized() * math.cos(q) + d * math.sin(q)) * 0.0024)
                 for q in [i * math.pi / 3 for i in range(6)]]
        tip = mb.vert(c + nrm * 0.0016)
        for i in range(6):
            mb.face((verts[i], verts[(i + 1) % 6], tip), "steel")


def build_cabin_details(parent):
    """Riveted strips along the frame members on the cabin walls, clamps at tube joints,
    rivets along the floor strip."""
    mb = MB()
    for side in (1, -1):
        wall = lambda y, z: Vector((side * (surface_x(y, z) - 0.0145), y, z))
        nrm = (-side, 0, 0)
        for y in (0.40, -0.55, -0.95):
            strip(mb, wall(y, -1.0), wall(y, -0.535), nrm)
        if side < 0:
            for y in (0.37, -0.07):  # left wall posts between the windows
                strip(mb, wall(y, -1.0), wall(y, -0.535), nrm)
        else:
            for y in (0.37, -0.07):  # door edges
                strip(mb, wall(y, -1.0), wall(y, -0.535), nrm, 0.022)
        for z in (-0.535, -0.80, -1.0):
            strip(mb, wall(0.42, z), wall(-1.30 if z < -0.6 else -0.95, z), nrm)
    # Clamps where the cross tubes meet the longerons inside the cabin.
    for y in [fy for fy in FRAME_Y if -1.5 < fy < 0.9]:
        sec = section(y, 0.028)
        for p in (sec[2], sec[7], sec[-2], sec[-7]):
            lathe(mb, [(-0.02, 0), (-0.02, 0.016), (0.02, 0.016), (0.02, 0)], "steel", p, "y", 10)
            box(mb, p + Vector((0, 0, 0.018)), (0.012, 0.02, 0.006), "steel")
    # Floor: rivets along both edges of the centre strip, nail heads on the planks.
    for y in [0.6 - k * 0.05 for k in range(29)]:
        for x in (-0.03, 0.03):
            lathe(mb, [(0, 0), (0, 0.003), (0.002, 0)], "steel", (x, y, FLOOR_Z - 0.001), "z", 6)
    for y in (0.55, 0.1, -0.35, -0.75):
        for x in (-0.20, -0.09, 0.09, 0.20):
            lathe(mb, [(0, 0), (0, 0.0025), (0.0015, 0)], "steel", (x, y, FLOOR_Z - 0.001), "z", 5)
    obj("Cabin_details", mb, parent, smooth=40)


# The instrument panel on the back of the fuel tank, 1.085 m ahead of the rear-seat eye.
# Gauge positions match aircraft/J3Cub/panel.tscn (eye-relative there).
EYE = Vector((0, -0.47, -0.30))
PANEL_Y = EYE.y + 1.085
PANEL_GAUGES = [(-0.165, -0.10, 0.08), (-0.055, -0.10, 0.08), (0.055, -0.10, 0.08), (0.140, -0.10, 0.05), (0.194, -0.10, 0.05)]


def build_panel(parent):
    mb = MB()
    cz, w, h = EYE.z - 0.10, 0.58, 0.21
    r = h / 2
    outline = []
    for cx, a0 in ((w / 2 - r, -90), (-(w / 2 - r), 90)):
        for k in range(13):
            t = math.radians(a0 + k * 15)
            outline.append((cx + r * math.cos(t), cz + r * math.sin(t)))
    front = mb.ring([Vector((x, PANEL_Y, z)) for x, z in outline])
    back = mb.ring([Vector((x, PANEL_Y + 0.012, z)) for x, z in outline])
    mb.loft([front, back], "panel", cap0=True, cap1=True)
    def screw(x, z, rad=0.0045, y=PANEL_Y):
        lathe(mb, [(0, 0), (0, rad), (0.0015, rad * 0.95), (0.003, rad * 0.6), (0.0035, 0)], "steel", (x, y, z), "y", 10, -1)
        box(mb, (x, y - 0.0036, z), (rad * 1.6, 0.0008, rad * 0.28), "engine")  # slot

    def flange(cx, cz, sx, sz, rad, depth=0.003):
        pts = []
        for ox, oz, a0 in ((sx / 2 - rad, sz / 2 - rad, 0), (-sx / 2 + rad, sz / 2 - rad, 90),
                           (-sx / 2 + rad, -sz / 2 + rad, 180), (sx / 2 - rad, -sz / 2 + rad, 270)):
            for k in range(5):
                t = math.radians(a0 + k * 22.5)
                pts.append((cx + ox + rad * math.cos(t), cz + oz + rad * math.sin(t)))
        f = mb.ring([Vector((x, PANEL_Y - depth, z)) for x, z in pts])
        b = mb.ring([Vector((x, PANEL_Y, z)) for x, z in pts])
        mb.loft([f, b], "bezel", cap0=True)

    def bezel_ring(cx, cz, d):
        lathe(mb, [(0, 0.57 * d), (0.009, 0.555 * d), (0.0105, 0.525 * d), (0.0098, 0.49 * d), (0.004, 0.482 * d),
                   (0.0, 0.482 * d)], "bezel", (cx, PANEL_Y - 0.003, cz), "y", 40, -1, open_ends=True)

    for k, (x, z) in enumerate(outline):
        if k % 3 == 0:
            screw(x * 0.94, cz + (z - cz) * 0.88)
    for gx, gz, d in PANEL_GAUGES[:3]:
        flange(gx, EYE.z + gz, d * 1.2, d * 1.2, d * 0.2)
        bezel_ring(gx, EYE.z + gz, d)
        for sx in (-1, 1):
            for sz in (-1, 1):
                screw(gx + sx * d * 0.47, EYE.z + gz + sz * d * 0.47, 0.0032, PANEL_Y - 0.003)
    # Combined oil temperature / pressure instrument: one case, two dials.
    flange(0.167, EYE.z - 0.10, 0.128, 0.072, 0.014)
    for gx, gz, d in PANEL_GAUGES[3:]:
        bezel_ring(gx, EYE.z + gz, d)
    for sx in (-1, 1):
        for sz in (-1, 1):
            screw(0.167 + sx * 0.056, EYE.z - 0.10 + sz * 0.028, 0.0028, PANEL_Y - 0.003)
    # Placards under the knobs (the engraving is drawn by the game).
    for x, z in ((-0.248, -0.164), (0.205, -0.193), (-0.165, -0.197)):
        box(mb, (x, PANEL_Y - 0.002, EYE.z + z), (0.05, 0.003, 0.013), "placard")
        for sx in (-1, 1):
            lathe(mb, [(0, 0), (0, 0.0015), (0.001, 0)], "steel", (x + sx * 0.022, PANEL_Y - 0.0035, EYE.z + z), "y", 6, -1)
    box(mb, (0.0, PANEL_Y + 0.02, EYE.z + 0.005), (0.07, 0.05, 0.012), "engine")
    obj("Panel_board", mb, parent, smooth=40)


def build_center_section(root):
    """Wing centre section over the cabin: skylight in the front half, fabric behind."""
    mb = MB()
    xs = [k / 12 for k in range(13)]
    cols = [-FUS_SIDE, -FUS_SIDE / 2, 0.0, FUS_SIDE / 2, FUS_SIDE]
    rings = []
    for X in cols:
        side = 1 if X >= 0 else -1
        pts = [wing_mapper(side)(abs(X), WING_LE - x * (WING_LE - WING_TE), naca4412(x, WING_LE - WING_TE)[0])
               for x in xs]
        uvs = [(0.005 + 0.19 * (X + FUS_SIDE) / (2 * FUS_SIDE), 0.80 + 0.19 * x) for x in xs]
        rings.append(mb.ring(pts, uvs))
    for i in range(len(cols) - 1):
        for j in range(len(xs) - 1):
            a, b = rings[i], rings[i + 1]
            mb.face((a[j], a[j + 1], b[j + 1], b[j]), "glass" if xs[j] < 0.5 else "tex_wing")
    obj("Center_section", mb, root, smooth=50)
    fb = MB()
    top = lambda X, x: wing_mapper(1 if X >= 0 else -1)(abs(X), WING_LE - x * (WING_LE - WING_TE),
                                                       naca4412(x, WING_LE - WING_TE)[0] + 0.006)
    tube(fb, [top(0, x) for x in (0.0, 0.1, 0.25, 0.4, 0.5)], 0.008, "cowl_edge", 6)
    for x in (0.25, 0.5):
        tube(fb, [top(X, x) for X in (-FUS_SIDE, 0, FUS_SIDE)], 0.008, "cowl_edge", 6)
    obj("Skylight_frame", fb, root, smooth=60)


def build_tail_parts(root):
    """Fairings where the tail meets the fuselage, and inspection covers."""
    mb = MB()
    for side in (1, -1):
        root_pts = [Vector((side * (half_width(y) + 0.004), y, STAB_Z + 0.004)) for y in (-3.76, -3.95, -4.15, -4.30)]
        tube(mb, root_pts, 0.032, "cowl_edge", 8, squash=0.35, flat_axis=(0, 0, 1))
    fin_base = [Vector((0, y, interp(FUS, y, 3) + 0.004)) for y in (-3.70, -3.95, -4.20, -4.45)]
    tube(mb, fin_base, 0.035, "cowl_edge", 8, squash=0.4, flat_axis=(1, 0, 0))
    obj("Tail_fairings", mb, root, smooth=50)
    cb = MB()
    for side in (1, -1):
        for y, z in ((-2.25, -0.76), (-3.35, -0.70), (-1.55, -0.88)):
            c = Vector((side * (surface_x(y, z) + 0.001), y, z))
            lathe(cb, [(0, 0), (0, 0.045), (0.004, 0.045), (0.004, 0)], "blue", c, "x", 16, side)
    for y in (-1.9, -3.0):
        lathe(cb, [(0, 0), (0, 0.05), (0.004, 0.05), (0.004, 0)], "blue",
              (0, y, interp(FUS, y, 2) - 0.001), "z", 16, -1)
    obj("Inspection_covers", cb, root, smooth=50)


FRAME_Y = [1.0, 0.40, -0.55, -0.95, -1.45, -2.0, -2.6, -3.2, -3.8, -4.3, -4.58]


def build_frame(parent):
    """Welded steel tube truss inside the fabric: longerons, uprights, cross tubes, diagonals."""
    mb = MB()
    nodes = []
    for y in FRAME_Y:
        sec = section(y, 0.028)
        lo_r, up_r = sec[2], sec[7]
        lo_l, up_l = sec[-2], sec[-7]
        nodes.append((lo_r, up_r, lo_l, up_l))
        tube(mb, [lo_r, up_r], 0.010, "frame", 6)
        tube(mb, [lo_l, up_l], 0.010, "frame", 6)
        tube(mb, [lo_r, lo_l], 0.010, "frame", 6)
        tube(mb, [up_r, up_l], 0.010, "frame", 6)
    for (a, b) in zip(nodes, nodes[1:]):
        for k in range(4):
            tube(mb, [a[k], b[k]], 0.012, "frame", 6)  # longerons
        if b[0].y < -0.95:  # no diagonals across the door and windows
            tube(mb, [a[0], b[1]], 0.009, "frame", 6)  # side diagonals
            tube(mb, [a[2], b[3]], 0.009, "frame", 6)
        tube(mb, [a[0], b[2]], 0.008, "frame", 6)  # floor diagonal
    obj("Frame", mb, parent, smooth=60)
    # Firewall and the nose fuel tank behind it (the panel hangs off the tank).
    fb = MB()
    ring = fb.ring(section(1.0, 0.004))
    fb.face(ring, "tank")  # firewall: dark painted sheet
    obj("Firewall", fb, parent, smooth=0)
    tb = MB()
    box(tb, (0, 0.80, -0.42), (0.40, 0.34, 0.17), "tank")  # hidden behind the panel
    obj("Fuel_tank", tb, parent, smooth=0)


def build_fuselage(root):
    mb = MB()
    rings = [mb.ring(*fus_uv_ring(section(y), y)) for y in STATIONS]
    mid = [(STATIONS[i] + STATIONS[i + 1]) / 2 for i in range(len(STATIONS) - 1)]
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(len(a) - 1):
            mb.face((a[j], a[j + 1], b[j + 1], b[j]), fus_material(mid[i], band_of(j)), band_of(j))
    mb.face(rings[-1], "tex_fus", 0)  # tail post
    first = rings[0]
    for j in range(len(first) - 1):
        nose = mb.vert((0, FUS_Y0, -0.62), (0.004, mb.uv[first[j]][1]))
        mb.face((first[j + 1], first[j], nose), "tex_fus", band_of(j))
    mb = cut_windows(mb)
    fus = empty("Fuselage", (0, 0, 0), parent=root)
    cowl = empty("Cowling", (0, 0, 0), parent=root)
    glaz = empty("Glazing", (0, 0, 0), parent=fus)
    door_lo = empty("DoorHinge_lower_R", (FUS_SIDE, 0.15, -1.04), parent=fus)
    door_up = empty("DoorHinge_upper_R", (FUS_SIDE - 0.02, 0.15, -0.07), parent=fus)
    parents = {"Nose_bowl": cowl, "Cowl_top_L": cowl, "Cowl_top_R": cowl, "Cowl_side_L": cowl,
               "Cowl_side_R": cowl, "Cowl_bottom": cowl, "Door_lower_R": door_lo, "Door_window_R": door_up,
               "Windshield": glaz, "Window_L_front": glaz, "Window_L_rear": glaz, "Window_R_rear": glaz}
    parts = {}
    for name, sub in split_parts(mb).items():
        if name is None:
            continue
        parts[name] = obj(name, sub, parents.get(name, fus), recalc=False,
                          smooth=80 if parents.get(name) is cowl else 55)
    for name in ("Nose_bowl", "Cowl_top_L", "Cowl_top_R", "Cowl_side_L", "Cowl_side_R", "Cowl_bottom"):
        SOLID.append((name, 0.004))
    SOLID.append(("Door_lower_R", 0.008))
    build_frame(fus)
    build_glazing_frames(fus)

    # Cabin lining seen from the seats: inset fabric, inward-facing, windows cut exactly.
    ib = MB()
    cab = [y for y in STATIONS if 1.0 >= y >= -1.6]
    irings = [ib.ring(*fus_uv_ring(section(y, 0.012), y)) for y in cab]
    for i in range(len(cab) - 1):
        ym = (cab[i] + cab[i + 1]) / 2
        a, b = irings[i], irings[i + 1]
        for j in range(len(a) - 1):
            band = band_of(j)
            if fus_material(ym, band) == "glass" or (band >= 8 and -0.42 < ym < 0.42):
                continue
            ib.face((b[j], b[j + 1], a[j + 1], a[j]), "tex_int", band)
    ib.face(irings[0][:-1], "interior")
    ib.face(list(reversed(irings[-1][:-1])), "interior")
    ib = cut_windows(ib)
    keep = MB()
    remap = {}
    for idx, m, tg in zip(ib.f, ib.m, ib.tag):
        if m == "glass":
            continue  # window openings
        keep.face([remap.setdefault(v, keep.vert(ib.v[v], ib.uv[v])) for v in idx], m, tg)
    obj("Interior", keep, root, recalc=False, smooth=40)

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
AIL0, AIL1, AIL_C = 2.55, 4.50, 0.785
TIP_LE0, TIP_TE0 = 5.02, 4.55  # where the leading / trailing edge start curving into the tip bow


def wing_mapper(side):
    def f(s, y, z):
        yr = y * math.cos(INC) - z * math.sin(INC)
        zr = y * math.sin(INC) + z * math.cos(INC)
        return Vector((side * s, yr, zr + s * math.tan(DIH)))
    return f


def wing_station(s):
    """Planform: straight wing, tip bow asymmetric (the tip point sits near the front spar)."""
    tip_y = WING_LE - 0.30 * (WING_LE - WING_TE)
    le, te = WING_LE, WING_TE
    if s > TIP_LE0:
        le = tip_y + (WING_LE - tip_y) * math.sqrt(max(0.0, 1 - ((s - TIP_LE0) / (HALF - TIP_LE0)) ** 2))
    if s > TIP_TE0:
        te = tip_y - (tip_y - WING_TE) * math.sqrt(max(0.0, 1 - ((s - TIP_TE0) / (HALF - TIP_TE0)) ** 2))
    if le - te < 0.02:
        le, te = tip_y + 0.01, tip_y - 0.01
    return (s, le, te)


def build_wing(root):
    tip_s = [AIL1, 4.55, 4.70, 4.85, 4.98, 5.08, 5.17, 5.24, 5.30, 5.34, 5.36, 5.37]
    for side, tag in ((1, "R"), (-1, "L")):
        mp = wing_mapper(side)
        uv = chord_uv(0.005 if side > 0 else 0.505, 0.49, HALF, 0.01, 0.76)
        mb, tb = MB(), MB()
        for st, c1, n in (([FUS_SIDE, 0.6, 1.0, 1.6, 2.1, AIL0], 1.0, 16), ([AIL0, 3.2, 3.9, AIL1], AIL_C, 14)):
            surface(mb, [wing_station(s) for s in st], 0.0, c1, naca4412, mp, "tex_wing", n, uv, "cream")
        surface(tb, [wing_station(s) for s in tip_s], 0.0, 1.0, naca4412, mp, "tex_wing", 16, uv, "cream")
        w = empty("Wing_" + tag, (0, 0, 0), parent=root)
        obj("Wing_panel_" + tag, mb, w, smooth=50)
        obj("Wingtip_" + tag, tb, w, smooth=50)

    for side, tag in ((1, "R"), (-1, "L")):
        mp = wing_mapper(side)
        y_h = WING_LE - AIL_C * (WING_LE - WING_TE)
        zc = sum(naca4412(AIL_C, WING_LE - WING_TE)) / 2
        hinge = empty("Hinge_aileron_" + tag, mp(AIL0 + 0.02, y_h, zc), (0, -side * DIH, 0),
                      bpy.data.objects["Wing_" + tag])
        ab = MB()
        uv = chord_uv(0.005 if side > 0 else 0.505, 0.49, HALF, 0.80, 0.19, AIL_C + 0.005, 1.0)
        surface(ab, [wing_station(s) for s in [AIL0 + 0.02, 3.2, 3.9, AIL1 - 0.02]], AIL_C + 0.005, 1.0,
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
    eb = MB()
    for side in (1, -1):
        mp = lambda s, y, z, side=side: Vector((side * s, y, STAB_Z + z))
        u0 = 0.005 if side > 0 else 0.255
        sb = MB()
        surface(sb, [stab_station(s) for s in st], 0.0, h, slab(0.022, taper_back=False), mp, "tex_tail", 10,
                chord_uv(u0, 0.24, 1.45, 0.01, 0.98), "cream")
        obj("Stab_" + ("R" if side > 0 else "L"), sb, root, smooth=50)
        surface(eb, [stab_station(s) for s in [0.07] + st[1:]], h, 1.0, slab(0.022, True, x0=h), mp, "tex_tail", 6,
                chord_uv(u0, 0.24, 1.45, 0.01, 0.98), "cream")
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
        foot = Vector((side * (FUS_SIDE - 0.01), -0.10, -1.03))
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
TYRE_R, TYRE_W = 0.29, 0.20  # 8.00-4 balloon tyres
AXLE_Y, AXLE_Z, AXLE_X = 0.36, -74.18 * 0.0254 + TYRE_R, 0.91  # J3Cub.xml main gear x -14.17 in
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
        for c in ((side * FUS_SIDE, 0.50, -1.04), (side * FUS_SIDE, -0.10, -1.04)):
            box(mb, c, (0.03, 0.05, 0.03), "blue")
    box(mb, (0, AXLE_Y, -1.13), (0.07, 0.06, 0.04), "steel")
    # Tail post fitting for the leaf spring.
    box(mb, (0, -4.40, -0.72), (0.04, 0.08, 0.03), "steel")
    obj("Gear_fixed", mb, root, smooth=60)

    for side, tag in ((1, "R"), (-1, "L")):
        axle = Vector((side * AXLE_X, AXLE_Y, AXLE_Z))
        inner = axle - Vector((side * (TYRE_W / 2 + 0.01), 0, 0))
        w = empty("Wheel_" + tag, tuple(axle), parent=root)
        wb = MB()
        tyre(wb, TYRE_R, TYRE_W, hub_r=0.115)
        for k in range(6):  # hub bolts
            a = k * math.pi / 3
            lathe(wb, [(0.0, 0), (0.0, 0.011), (0.012, 0.011), (0.012, 0)], "steel",
                  (side * TYRE_W * 0.38, 0.06 * math.cos(a), 0.06 * math.sin(a)), "x", 6, side)
        wb.v = [tuple(Vector(p) + axle) for p in wb.v]
        obj("Tyre_" + tag, wb, w, smooth=60)
        empty("Axle_" + tag, tuple(inner), parent=w)  # on the spin axis, so spinning doesn't move it

        hinge = Vector((side * 0.03, AXLE_Y, -1.13))
        rear = Vector((side * FUS_SIDE, -0.10, -1.04))
        top = Vector((side * FUS_SIDE, 0.50, -1.04))
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


def finned_block(mb, base, sx, sy, height, n_fins, mat):
    """Air-cooled cylinder head: a stack of rounded-rectangle cooling fins rising from base."""
    def rr(scale, z):
        hx, hy, k = sx / 2 * scale, sy / 2 * scale, 0.015
        pts = []
        for cx, cy, a0 in ((hx - k, hy - k, 0), (-hx + k, hy - k, 90), (-hx + k, -hy + k, 180), (hx - k, -hy + k, 270)):
            for a in (0, 45, 90):
                t = math.radians(a0 + a)
                pts.append(base + Vector((cx + k * math.cos(t), cy + k * math.sin(t), z)))
        return mb.ring(pts)
    rings = []
    step = height / n_fins
    for i in range(n_fins):
        z = i * step
        rings += [rr(0.80, z), rr(1.0, z + step * 0.15), rr(1.0, z + step * 0.45), rr(0.80, z + step * 0.6)]
    rings.append(rr(0.80, height))
    mb.loft(rings, mat, cap0=True, cap1=True)


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
    # Fuel tank cap with the cork-float wire gauge in front of the windscreen.
    lathe(mb, [(0, 0), (0, 0.035), (0.022, 0.035), (0.022, 0)], "steel", (0, 0.93, -0.226), "z", 12)
    tube(mb, [(0, 0.93, -0.20), (0, 0.93, 0.02), (0, 0.97, 0.02)], 0.003, "steel", 5)
    # Air inlet grille in the nose bowl chin.
    box(mb, (0, 1.712, -0.745), (0.17, 0.012, 0.065), "cavity")
    for k in range(-4, 5):
        box(mb, (k * 0.018, 1.718, -0.745), (0.005, 0.01, 0.062), "engine")
    # Carburettor air scoop under the cowl.
    lathe(mb, [(0, 0), (0, 0.045), (0.16, 0.04), (0.17, 0)], "blue", (0, 1.38, -1.0), "y", 12, -1)
    lathe(mb, [(0, 0), (0, 0.036), (0.005, 0.036), (0.005, 0)], "cavity", (0, 1.381, -1.0), "y", 12)
    # Pitot tube under the left wing.
    base = wing_bottom(-1, 3.4, 0.25)
    tube(mb, [base, base + Vector((0, 0, -0.10)), base + Vector((0, 0.18, -0.10))], 0.006, "steel", 6)
    # Door handle, right side.
    box(mb, (FUS_SIDE + 0.006, -0.03, -0.62), (0.012, 0.07, 0.015), "steel")
    obj("Details", mb, root, smooth=50)


PROP = Vector((0, 1.75, -0.62))
PROP_R = 0.915


def build_engine(root):
    """Continental A-65 type flat four: crankcase, four finned cylinders, carburettor,
    magnetos, intake and exhaust, mount. Each part its own object."""
    eng = empty("Engine", (0, 0, 0), parent=root)
    cb = MB()
    box(cb, (0, 1.36, -0.56), (0.30, 0.40, 0.22), "engine")
    box(cb, (0, 1.36, -0.70), (0.22, 0.30, 0.08), "engine")  # oil sump
    lathe(cb, [(0, 0), (0, 0.05), (0.04, 0.05), (0.04, 0)], "steel", (0, 1.57, -0.62), "y", 12)  # prop flange
    obj("Engine_crankcase", cb, eng, smooth=30)
    fins = []
    for k in range(8):
        fins += [(k * 0.016, 0.054), (k * 0.016 + 0.008, 0.072)]
    n = 0
    xb = MB()
    for side in (1, -1):
        y0, z0, ay, az = CYL_OPEN[side]
        for y in (y0 - 0.083, y0 + 0.083):
            n += 1
            m = MB()
            sx = surface_x(y, z0)
            hx = sx + 0.03  # head centre: sticks out of the opening a few centimetres
            head = Vector((side * hx, y, z0))
            finned_block(m, head + Vector((0, 0, -0.065)), 0.11, 0.115, 0.12, 8, "engine")
            box(m, head + Vector((0, 0, 0.075)), (0.095, 0.105, 0.035), "engine")  # rocker cover
            box(m, head + Vector((0, 0, 0.096)), (0.07, 0.08, 0.008), "steel")
            lathe(m, [(0, 0)] + fins + [(0.13, 0.054), (0.13, 0)], "engine",
                  head - Vector((side * 0.055, 0, 0)), "x", 12, -side)  # barrel, inside the cowl
            plug = head + Vector((side * 0.057, 0.025, 0.02))
            lathe(m, [(0, 0), (0, 0.009), (0.025, 0.009), (0.025, 0)], "steel", plug, "x", 6, side)
            tube(m, [plug + Vector((side * 0.025, 0, 0)), plug + Vector((side * 0.035, 0, 0.03)),
                     plug + Vector((side * 0.0, -0.05, 0.06)), plug + Vector((-side * 0.06, -0.12, 0.06))],
                 0.005, "tyre", 5)  # ignition lead, back over the head towards the magnetos
            obj(f"Engine_cylinder_{n}", m, eng, smooth=40)
            # Exhaust: down from the head into a collector along the cowl side.
            port = head + Vector((side * 0.02, 0, -0.07))
            tube(xb, [port, port + Vector((side * 0.02, -0.01, -0.06)),
                      Vector((side * (surface_x(y - 0.03, -0.645) + 0.032), y - 0.04, -0.645))], 0.022, "exhaust", 10)
        ys = [y0 + 0.06, y0 - 0.12, 1.22, 1.10]
        tube(xb, [Vector((side * (surface_x(yy, -0.645) + 0.032), yy, -0.645)) for yy in ys], 0.026, "exhaust", 12)
        boss = Vector((side * (surface_x(1.06, -0.645) - 0.01), 1.06, -0.645))
        lathe(xb, [(0, 0.06), (0, 0.065), (0.035, 0.065), (0.035, 0.045), (0.02, 0.03), (0.02, 0)],
              "exhaust", boss, "x", 16, side)  # carb heat muff where the pipe enters
    obj("Engine_exhaust", xb, eng, smooth=45)
    rim = MB()
    for side in (1, -1):
        y0, z0, ay, az = CYL_OPEN[side]
        pts = []
        for k in range(29):
            t = 2 * math.pi * k / 28
            y, z = y0 + ay * math.cos(t), z0 + az * math.sin(t)
            pts.append(Vector((side * (surface_x(y, z) + 0.004), y, z)))
        tube(rim, pts, 0.008, "cowl_edge", 6, cap=False)
        # Dark cavity behind the heads so the opening reads as a hole.
        cav = [Vector((side * (surface_x(p.y, p.z) - 0.10), p.y, p.z)) for p in pts[:-1]]
        ring = [rim.vert(p) for p in cav]
        rim.face(ring, "cavity")
    obj("Cowl_openings", rim, bpy.data.objects["Cowling"], smooth=50)
    ib = MB()
    box(ib, (0, 1.22, -0.78), (0.08, 0.09, 0.10), "steel")  # carburettor
    for side in (1, -1):
        tube(ib, [(0, 1.22, -0.73), (side * 0.10, 1.25, -0.66), (side * 0.20, 1.38, -0.58)], 0.016, "steel", 8)
    obj("Engine_carburettor", ib, eng, smooth=45)
    mg = MB()
    for side in (1, -1):
        lathe(mg, [(0, 0), (0, 0.042), (0.11, 0.042), (0.11, 0)], "engine", (side * 0.08, 1.15, -0.44), "y", 12, -1)
        tube(mg, [(side * 0.08, 1.06, -0.42), (side * 0.20, 1.20, -0.40)], 0.006, "tyre", 5)
    obj("Engine_magnetos", mg, eng, smooth=45)
    mt = MB()
    for sx in (1, -1):
        for sz in (1, -1):
            tube(mt, [(sx * 0.13, 1.18, -0.56 + sz * 0.09), (sx * 0.27, 1.0, -0.62 + sz * 0.30)], 0.011, "frame", 6)
    obj("Engine_mount", mt, eng, smooth=60)


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
    lathe(sb, [(-0.02, 0), (-0.02, 0.068), (0.03, 0.064), (0.075, 0.042), (0.11, 0.016), (0.125, 0)],
          "engine", PROP, "y", 16)
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
        set_parent(ob, bpy.data.objects["Skin_" + ("R" if side > 0 else "L")])  # painted on that panel


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
    seam = np.exp(-((y - 1.0) / 0.003) ** 2) + np.exp(-((y - 1.60) / 0.003) ** 2) * cowl
    seam += np.exp(-((z - zs) / 0.003) ** 2) * cowl * (y < 1.60)
    seam += np.exp(-(x / 0.004) ** 2) * cowl * (z > zt - 0.05) * (y < 1.60)  # top cowl halves meet
    col = pt.mix(col, col * 0.35, np.clip(seam, 0, 1) * 0.8)
    rivet_row = (np.abs(y - 1.0) < 0.012) | ((np.abs(y - 1.60) < 0.012) & cowl)
    rv = ((np.abs((z + 0.0175) % 0.035 - 0.0175) < 0.004) & rivet_row).astype(np.float32)
    height += rv * 0.3
    col = pt.mix(col, col * 0.7, rv * 0.35)

    # Cylinder openings: dark engine bay seen through the cowl, rivets round the edge.
    for sgn, (oy, oz, ay, az) in CYL_OPEN.items():
        e = np.sqrt(((y - oy) / ay) ** 2 + ((z - oz) / az) ** 2)
        on = (np.sign(x) == sgn) & cowl
        hole = (e < 1.0) & on
        col = np.where(hole[:, None], np.array([0.012, 0.010, 0.009], np.float32), col)
        ring = on & (e > 1.05) & (e < 1.16)
        ang = np.arctan2((z - oz) / az, (y - oy) / ay)
        rv2 = ring & (np.abs(((ang * 14 / np.pi) % 1.0) - 0.5) < 0.12)
        col = pt.mix(col, col * 0.55, rv2.astype(np.float32) * 0.6)
        height += rv2 * 0.3
        stain = on & (e < 1.8) & (e >= 1.0)
        col = pt.mix(col, SOOT, stain * np.clip(1.8 - e, 0, 1) * 0.35 * pt.fbm(P, 20.0, 2, seed=17))
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

    side = lambda sx, yc, zc_, ha, hb: ((sx * FUS_SIDE, yc, zc_), (0, 1, 0), (0, 0, 1), ha, hb)
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


def rules_interior(P, Nn, part):
    """Cabin fabric: cream cloth, stitched panel seams, water stains, boot scuffs low down."""
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    col = np.tile(C("#C8BB98"), (len(P), 1)).astype(np.float32)
    rough = np.full(len(P), 0.9, np.float32)
    metal = np.zeros(len(P), np.float32)
    height = np.zeros(len(P), np.float32)
    col *= (0.93 + 0.12 * pt.fbm(P, 3.0, 4, seed=20))[:, None]
    col *= (0.96 + 0.06 * pt.fbm(P, 260.0, 2, seed=21))[:, None]  # weave
    stains = pt.smoothstep(pt.fbm(P, 6.0, 4, seed=22), 0.58, 0.72)
    col = pt.mix(col, col * np.array([0.72, 0.62, 0.46], np.float32), stains * 0.55)
    # Deep footwell under the panel is in shadow; dirt and boot scuffs near the floor.
    well = pt.smoothstep(y, 0.35, 0.95) * pt.smoothstep(-z, 0.45, 0.9)
    col *= (1.0 - 0.6 * well)[:, None]
    low = pt.smoothstep(-z, 0.80, 1.05)
    col = pt.mix(col, col * np.array([0.55, 0.50, 0.42], np.float32), low * (0.4 + 0.4 * pt.fbm(P, 12.0, 3, seed=23)))
    s_in, s_edge = tape(y, 0.30, 0.0, 0.012)
    h_in, h_edge = tape(z, 0.30, -0.55, 0.012)
    seam = np.maximum(s_in, h_in)
    height += seam * 0.6
    col = pt.mix(col, col * 0.72, np.maximum(s_edge, h_edge) * 0.6)
    st = np.maximum(stitches(z, (y + 0.15) % 0.30 - 0.15, 0.03), stitches(y, (z + 0.70) % 0.30 - 0.15, 0.03))
    col = pt.mix(col, col * 0.5, st * 0.6)
    pm, ps = patches(P, Nn, [((-FUS_SIDE + 0.012, -0.70, -0.62), (0, 1, 0), (0, 0, 1), 0.07, 0.06),
                             ((FUS_SIDE - 0.012, -0.85, -0.80), (0, 1, 0), (0, 0, 1), 0.06, 0.05)])
    col = pt.mix(col, SILVER * 1.1, pm * 0.7)
    col = pt.mix(col, col * 0.45, ps)
    return col, rough, metal, height


# --- cabin parts: shared texture sheets, painted per material, with contact shadows ---

# The panel, the seats and the tube frame get their own sheets so the parts you look at
# most get the most detail.
CABIN_SHEETS = {
    "cab": ["Cabin_fixed", "Cabin_details", "Stick_rear_mesh", "Stick_front_mesh", "Pedals_rear_mesh", "Pedals_front_mesh",
            "HeelBrake_L_mesh", "HeelBrake_R_mesh", "Throttle_rear_quadrant", "Throttle_front_quadrant",
            "Throttle_rear_lever", "Throttle_front_lever", "Throttle_rod", "Trim_crank_mesh", "Firewall",
            "Fuel_tank", "Window_frames", "Skylight_frame"],
    "pnl": ["Panel_board"],
    "seat": ["Seat_rear", "Seat_front"],
    "frm": ["Frame"],
}
CABIN_MATS = {"Frame_Tube": 10, "Seat_Leather": 11, "Floor_Wood": 12, "Pedal_Metal": 13, "Steel": 14,
              "Engine_Black": 15, "Seat_Belt": 16, "Paper_Map": 17, "Brass": 18, "Panel_Paint": 19, "Bezel": 20,
              "Placard": 21, "Fuel_Tank": 22, "Cowl_Edge": 23, "Tyre": 24}


def unwrap_cabin(objs):
    wm = bpy.context.window_manager
    win = wm.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D")
    region = next(r for r in area.regions if r.type == "WINDOW")
    with bpy.context.temp_override(window=win, area=area, region=region, active_object=objs[0],
                                   selected_objects=objs, selected_editable_objects=objs, object=objs[0]):
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003)
        bpy.ops.uv.pack_islands(margin=0.003)
        bpy.ops.object.mode_set(mode="OBJECT")


def cabin_bvh():
    """Everything a ray from inside the cabin can hit."""
    from mathutils.bvhtree import BVHTree
    verts, polys = [], []
    for o in COLL.objects:
        if o.type != "MESH" or o.name.startswith(("Wing", "Stab", "Elevator", "Fin", "Rudder", "Tyre", "Blades", "Disc")):
            continue
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        polys += [[base + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def rules_cabin(P, Nn, part):
    """Worn paint, leather, wood and metal for the cabin parts, chosen by original material."""
    n = len(P)
    col = np.zeros((n, 3), np.float32)
    rough = np.full(n, 0.6, np.float32)
    metal = np.zeros(n, np.float32)
    height = np.zeros(n, np.float32)
    up = np.clip(Nn[:, 2], 0, 1)
    dust = pt.fbm(P, 4.0, 3, seed=30)
    fine = pt.fbm(P, 140.0, 2, seed=31)

    def sel(i):
        return part == i

    # Frame tubes: blue-grey enamel, chipped to rust and bare steel, dusty on top.
    m = sel(10)
    if m.any():
        p = P[m]
        base = np.tile(C("#5B7E8E"), (m.sum(), 1)) * (0.9 + 0.2 * pt.fbm(p, 6.0, 3, seed=32))[:, None]
        chip = pt.smoothstep(pt.fbm(p, 55.0, 3, seed=33), 0.66, 0.69)
        speck = pt.smoothstep(pt.fbm(p, 220.0, 2, seed=34), 0.72, 0.74)
        rust = pt.mix(np.tile(C("#4B3324"), (m.sum(), 1)), np.tile(C("#7A6A58"), (m.sum(), 1)), pt.fbm(p, 90.0, 2, seed=35))
        c = pt.mix(base, rust, np.clip(chip + speck * 0.8, 0, 1))
        c = pt.mix(c, c * 0.6, pt.smoothstep(pt.fbm(p, (3, 3, 18), 3, seed=36), 0.6, 0.8) * 0.5)  # rust runs
        col[m] = c
        rough[m] = 0.5 + 0.3 * chip
        metal[m] = 0.15 + 0.4 * speck
        height[m] = -chip * 0.4
    # Seat leather: dark navy, a network of fine tan cracks, rubbed light where you sit.
    m = sel(11)
    if m.any():
        p = P[m]
        base = np.tile(C("#232A31"), (m.sum(), 1)) * (0.85 + 0.3 * pt.fbm(p, 8.0, 3, seed=40))[:, None]
        n1 = pt.fbm(p, 28.0, 4, seed=41)
        n2 = pt.fbm(p, 70.0, 3, seed=42)
        crack = np.clip(1.0 - np.abs(n1 - 0.5) / 0.009, 0, 1) + 0.6 * np.clip(1.0 - np.abs(n2 - 0.5) / 0.006, 0, 1)
        crack = np.clip(crack, 0, 1)
        rub = pt.smoothstep(pt.fbm(p, 5.0, 3, seed=43), 0.45, 0.75) * up[m]
        c = pt.mix(base, base * 1.8 + 0.02, rub * 0.6)
        c = pt.mix(c, np.tile(C("#7E6444"), (m.sum(), 1)), crack * 0.7)
        seam = np.exp(-((np.abs(p[:, 0]) - 0.11) / 0.003) ** 2)  # two stitched channels per cushion
        st = (np.abs(((p[:, 1] + p[:, 2]) % 0.012) - 0.006) < 0.002) & (np.abs(np.abs(p[:, 0]) - 0.104) < 0.002)
        c = pt.mix(c, c * 0.45, seam * 0.8)
        c = pt.mix(c, np.tile(C("#8B7A5E"), (m.sum(), 1)), st.astype(np.float32) * 0.8)
        height[m] = -seam * 0.8
        col[m] = c
        rough[m] = 0.45 + 0.35 * crack
        height[m] = np.minimum(height[m], -crack * 0.6)
    # Floorboards: wood grain along the planks, boot-worn, dirt stains.
    m = sel(12)
    if m.any():
        p = P[m]
        plank = np.floor(p[:, 0] / 0.112)
        tint = 0.8 + 0.4 * np.abs(np.sin(plank * 12.9898)) % 0.4
        grain = pt.fbm(p, (70.0, 2.5, 70.0), 4, seed=50)
        rings = 0.5 + 0.5 * np.sin(grain * 40.0)
        base = np.tile(C("#5A452E"), (m.sum(), 1)) * (tint * (0.75 + 0.35 * rings))[:, None]
        worn = pt.smoothstep(pt.fbm(p, 6.0, 3, seed=51), 0.5, 0.8)
        dirt = pt.smoothstep(pt.fbm(p, 12.0, 3, seed=52), 0.45, 0.75)
        c = pt.mix(base, base * 1.5, worn * 0.4)
        c = pt.mix(c, np.tile(C("#6B5A44"), (m.sum(), 1)), dirt * 0.5)
        col[m] = c
        rough[m] = 0.8
        height[m] = rings * 0.15
    # Panel: grey-green enamel, fine chips mostly at the edges, scratches, dust.
    m = sel(19)
    if m.any():
        p = P[m]
        base = np.tile(C("#38413C"), (m.sum(), 1)) * (0.9 + 0.2 * pt.fbm(p, 9.0, 3, seed=60))[:, None]
        rr = np.sqrt((p[:, 0] / 0.29) ** 2 + ((p[:, 2] - (EYE.z - 0.10)) / 0.105) ** 2)
        edge = pt.smoothstep(rr, 0.82, 1.0)
        chip = pt.smoothstep(pt.fbm(p, 110.0, 3, seed=61) + edge * 0.22, 0.81, 0.83)
        scratch = pt.smoothstep(pt.fbm(p, (260.0, 4.0, 18.0), 2, seed=62), 0.78, 0.8)
        c = pt.mix(base, np.tile(C("#8E8A80"), (m.sum(), 1)), chip)
        c = pt.mix(c, c * 1.4 + 0.03, scratch * 0.5)
        col[m] = c
        rough[m] = 0.55 - 0.2 * chip
        metal[m] = chip * 0.8
        height[m] = -chip * 0.3
    # Gauge flanges and bezels: black, worn brown on raised edges.
    m = sel(20)
    if m.any():
        p = P[m]
        wear = pt.smoothstep(pt.fbm(p, 80.0, 3, seed=63), 0.62, 0.68)
        col[m] = pt.mix(np.tile(C("#191817"), (m.sum(), 1)), np.tile(C("#5E4C3A"), (m.sum(), 1)), wear)
        rough[m] = 0.4 + 0.2 * wear
        metal[m] = 0.5 + 0.3 * wear
    # Small metal: bolts, latches, pulleys (steel), pedals, placards, aluminium frames, brass, tank.
    for i, hexc, r0, m0, rusty in ((14, "#8A8A86", 0.45, 0.9, 0.25), (13, "#5E584C", 0.5, 0.7, 0.6),
                                   (21, "#A5A194", 0.4, 0.8, 0.2), (23, "#B5AE9C", 0.45, 0.7, 0.3),
                                   (18, "#A8894A", 0.35, 1.0, 0.0), (22, "#45463F", 0.65, 0.3, 0.3)):
        m = sel(i)
        if not m.any():
            continue
        p = P[m]
        base = np.tile(C(hexc), (m.sum(), 1)) * (0.85 + 0.25 * pt.fbm(p, 20.0, 3, seed=70 + i))[:, None]
        rust = pt.smoothstep(pt.fbm(p, 25.0, 3, seed=80 + i), 0.64, 0.76) * rusty
        patina = pt.smoothstep(pt.fbm(p, 30.0, 3, seed=90 + i), 0.55, 0.75) * (i == 18)
        c = pt.mix(base, np.tile(C("#5A3A22"), (m.sum(), 1)), rust)
        c = pt.mix(c, np.tile(C("#4F5E3E"), (m.sum(), 1)), patina * 0.6)
        col[m] = c
        rough[m] = r0 + 0.3 * rust
        metal[m] = m0 * (1 - rust)
    # Black knobs, grips, quadrant: bakelite/rubber with scuffs.
    for i, hexc in ((15, "#151413"), (24, "#121212")):
        m = sel(i)
        if m.any():
            p = P[m]
            scuff = pt.smoothstep(pt.fbm(p, 90.0, 2, seed=95 + i), 0.65, 0.75)
            col[m] = pt.mix(np.tile(C(hexc), (m.sum(), 1)), np.tile(C("#3A3530"), (m.sum(), 1)), scuff * 0.6)
            rough[m] = 0.35 + 0.4 * scuff
    # Webbing belts: olive woven strap, dirty.
    m = sel(16)
    if m.any():
        p = P[m]
        weave = 0.85 + 0.15 * np.sin(pt.fbm(p, (300, 300, 300), 1, seed=96) * 30)
        col[m] = np.tile(C("#5E5B45"), (m.sum(), 1)) * (weave * (0.8 + 0.3 * pt.fbm(p, 15.0, 3, seed=97)))[:, None]
        rough[m] = 0.9
    # The chart in the map pocket: sea, islands, grid, a pencilled route.
    m = sel(17)
    if m.any():
        p = P[m]
        land = pt.smoothstep(pt.fbm(p, 9.0, 4, seed=98), 0.5, 0.52)
        coast = np.clip(1 - np.abs(pt.fbm(p, 9.0, 4, seed=98) - 0.51) / 0.006, 0, 1)
        c = pt.mix(np.tile(C("#A9C3CC"), (m.sum(), 1)), np.tile(C("#DCD2B0"), (m.sum(), 1)), land)
        c = pt.mix(c, np.tile(C("#4A6A78"), (m.sum(), 1)), coast * 0.8)
        grid = (np.abs(((p[:, 1] + 0.01) % 0.04) - 0.02) < 0.0008) | (np.abs(((p[:, 2] + 0.01) % 0.04) - 0.02) < 0.0008)
        c = pt.mix(c, c * 0.6, grid.astype(np.float32))
        route = np.abs((p[:, 2] + 0.66) - 0.35 * (p[:, 1] + 0.24)) < 0.0012
        c = pt.mix(c, np.tile(C("#8C2A1E"), (m.sum(), 1)), route.astype(np.float32))
        col[m] = c
        rough[m] = 0.9
    # Dust settles on everything facing up.
    col = pt.mix(col, col * 0.7 + np.array([0.12, 0.10, 0.07], np.float32), (up * dust * 0.35)[:, None])
    col *= (0.96 + 0.08 * fine)[:, None]
    return col, rough, metal, height


def paint_cabin():
    bvh = cabin_bvh()
    for key, names in CABIN_SHEETS.items():
        objs = [bpy.data.objects[n] for n in names if n in bpy.data.objects]
        unwrap_cabin(objs)
        W, H = IMGS[key]["base"].size
        items = [(o, CABIN_MATS, None) for o in objs]
        ao = pt.ambient_occlusion(items, W, H, bvh, rays=12, dist=0.22, down=max(2, int(8 * QUALITY)))
        pt.paint(items, W, H, rules_cabin, IMGS[key], TEX_DIR, normal_strength=2.0 * QUALITY, ao=ao)
        for o in objs:  # one textured material per sheet
            for i, m in enumerate(o.data.materials):
                if m and m.name in CABIN_MATS:
                    o.data.materials[i] = M["tex_" + key]
        print("painted cabin sheet", key, W, "x", H, len(objs), "parts")


def paint_all():
    os.makedirs(TEX_DIR, exist_ok=True)
    part_ids = {"Aileron": 3, "Elevator": 5, "Fin": 6, "Rudder": 7, "Stab": 4}
    jobs = {"fus": ("Cub_Fus", rules_fuselage, 1), "wing": ("Cub_Wing", rules_wing, 2),
            "tail": ("Cub_Tail", rules_tail, 4), "int": ("Cub_Int", rules_interior, 8)}
    for key, (mat, rules, default_id) in jobs.items():
        items = []
        for o in COLL.objects:
            if o.type == "MESH" and mat in [m.name for m in o.data.materials if m]:
                pid = next((v for k, v in part_ids.items() if o.name.startswith(k)), default_id)
                items.append((o, pid, {mat}))
        img = IMGS[key]["base"]
        W, H = img.size
        texels = pt.paint(items, W, H, rules, IMGS[key], TEX_DIR, normal_strength=3.0 * QUALITY)
        print("painted", key, W, "x", H, texels, "texels", len(items), "parts")

# --- main --------------------------------------------------------------------

def build():
    global COLL
    SOLID.clear()
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
    build_center_section(root)
    build_tail_parts(root)
    build_cabin(root)
    build_engine(root)
    build_prop(root)
    build_registration(root)
    bpy.context.view_layer.update()
    if globals().get("PAINT", True):
        paint_all()
        paint_cabin()
    apply_solidify()
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
