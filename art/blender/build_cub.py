"""Builds the Cub-type airframe in Blender and exports game/aircraft/J3Cub/model/cub.glb.

Run inside Blender:
    p = "<repo>/art/blender/build_cub.py"; exec(compile(open(p).read(), p, "exec"), {"__file__": p})

Frame: Blender X = right, Y = forward, Z = up, metres. Origin = JSBSim structural
origin, so the glTF lands in Godot exactly on Geo.struct_to_local (JSBSim x aft,
y right, z up, inches -> Blender (y, -x, z) * 0.0254). Dimensions from J3Cub.xml
(gear, prop, eyepoint, wing, tail arms) and published J-3 figures.

Node names follow game/aircraft/model_airframe.gd (hinges, Prop, Wheel_*, Steer_*).
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "game", "aircraft", "J3Cub", "model", "cub.glb")
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


M = {}
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
    M["reg"] = material("Registration", "#ECE4CC", 0.7, double=True)

# --- mesh building -------------------------------------------------------------

class MB:
    """Vertices + faces with a material key per face."""
    def __init__(self):
        self.v, self.f, self.m = [], [], []

    def vert(self, p):
        self.v.append(tuple(p))
        return len(self.v) - 1

    def face(self, idx, mat):
        self.f.append(list(idx))
        self.m.append(mat)

    def ring(self, pts):
        return [self.vert(p) for p in pts]

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


def tube(mb, pts, r, mat, sides=8, cap=True):
    """Round tube along a polyline."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        w = d.cross(u).normalized()
        rings.append(mb.ring([p + (u * math.cos(a) + w * math.sin(a)) * r
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
    (-4.30, 0.13, -0.76, -0.565),
    (-4.62, 0.035, -0.71, -0.60),
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
             (0.33 * w, zt - 0.012), (0, zt)]
    ring = right + [(-x, z) for x, z in reversed(right[1:-1])]
    return [Vector((x, y, z)) for x, z in ring]


def band_of(j, n_right=10):
    return j if j < n_right - 1 else 2 * (n_right - 1) - 1 - j


def windshield(y):
    return 0.42 < y < 0.97


def side_window(y):
    return -0.95 < y < 0.36 and not (-0.34 < y < -0.30)


def fus_material(y, band):
    if band <= 2 or band == 4:
        return "blue"
    if band in (3, 5):
        return "cream"
    if band == 6:
        return "glass" if (windshield(y) or side_window(y)) else "cream"
    return "glass" if windshield(y) else "cream"


def build_fuselage(root):
    mb = MB()
    rings = [mb.ring(section(y)) for y in STATIONS]
    mid = [(STATIONS[i] + STATIONS[i + 1]) / 2 for i in range(len(STATIONS) - 1)]
    mb.loft(rings, lambda i, j: fus_material(mid[i], band_of(j)), cap1=True)
    nose = mb.vert((0, 1.72, -0.62))
    first = rings[0]
    for j in range(len(first)):
        k = (j + 1) % len(first)
        mb.face((first[k], first[j], nose), fus_material(1.7, band_of(j)))
    obj("Fuselage", mb, root, smooth=40)

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


def surface(mb, stations, c0, c1, profile, mapper, mat, n=12):
    """stations: [(s, le, te)], chord along Y (le > te). Closed loft between c0..c1."""
    xs = [c0 + (c1 - c0) * (0.5 - 0.5 * math.cos(math.pi * k / (n - 1))) for k in range(n)]
    rings = []
    for s, le, te in stations:
        chord = max(le - te, 1e-4)
        up = [(x, profile(x, chord)[0]) for x in xs]
        lo = [(x, profile(x, chord)[1]) for x in reversed(xs)]
        if abs(up[-1][1] - lo[0][1]) < 1e-6:
            lo = lo[1:]
        if abs(up[0][1] - lo[-1][1]) < 1e-6:
            lo = lo[:-1]
        pts = [mapper(s, le - x * chord, z) for x, z in up + lo]
        rings.append(mb.ring(pts))
    mb.loft(rings, mat, cap0=True, cap1=True)
    return rings


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
        surface(mb, [wing_station(s) for s in [0.0, 0.5, 1.0, 1.6, 2.1, AIL0]], 0.0, 1.0, naca4412, mp, "cream", 16)
        surface(mb, [wing_station(s) for s in [AIL0, 3.2, 4.0, AIL1]], 0.0, AIL_C, naca4412, mp, "cream", 14)
        surface(mb, [wing_station(s) for s in tip_s], 0.0, 1.0, naca4412, mp, "blue", 16)
    obj("Wing", mb, root, smooth=50)

    for side, tag in ((1, "R"), (-1, "L")):
        mp = wing_mapper(side)
        y_h = WING_LE - AIL_C * (WING_LE - WING_TE)
        zc = sum(naca4412(AIL_C, WING_LE - WING_TE)) / 2
        hinge = empty("Hinge_aileron_" + tag, mp(AIL0 + 0.02, y_h, zc), (0, -side * DIH, 0), root)
        ab = MB()
        surface(ab, [wing_station(s) for s in [AIL0 + 0.02, 3.2, 4.0, AIL1 - 0.02]], AIL_C + 0.005, 1.0,
                naca4412, mp, "cream", 8)
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
    tip_mat = lambda i, j: "blue" if i >= 6 else "cream"
    for side in (1, -1):
        mp = lambda s, y, z, side=side: Vector((side * s, y, STAB_Z + z))
        surface(sb, [stab_station(s) for s in st], 0.0, h, slab(0.022, taper_back=False), mp, tip_mat, 10)
        surface(eb, [stab_station(s) for s in [0.07] + st[1:]], h, 1.0, slab(0.022, True, x0=h), mp, tip_mat, 6)
    obj("Stabilizer", sb, root, smooth=50)
    hinge = empty("Hinge_elevator", (0, STAB_HINGE, STAB_Z), parent=root)
    obj("Elevator", eb, hinge, smooth=50)

    def fin_le(s):
        if s <= 0.80:
            return -3.85 - 0.45 * s / 0.80
        return RUD_HINGE + 0.32 * math.sqrt(max(0.0, 1 - ((s - 0.80) / 0.18) ** 2))

    def rud_te(s):
        if s < -0.05:
            return lerp(-4.92, -5.00, (s + 0.13) / 0.08)
        if s <= 0.55:
            return -5.02
        return RUD_HINGE - 0.40 * math.sqrt(max(0.0, 1 - ((s - 0.55) / 0.43) ** 2))

    vmap = lambda s, y, z: Vector((z, y, FIN_Z0 + s))
    fb, rb = MB(), MB()
    fs = [0.0, 0.2, 0.4, 0.6, 0.8, 0.86, 0.91, 0.95, 0.975, 0.979]
    surface(fb, [(s, fin_le(s), RUD_HINGE) for s in fs], 0.0, 1.0, slab(0.018, taper_back=False), vmap, "cream", 10)
    rs = [-0.13, -0.05, 0.1, 0.3, 0.55, 0.65, 0.75, 0.84, 0.91, 0.95, 0.975, 0.979]
    surface(rb, [(s, RUD_HINGE, rud_te(s)) for s in rs], 0.0, 1.0, slab(0.018, True), vmap, "cream", 8)
    fin = obj("Fin", fb, root, smooth=50)
    hinge = empty("Hinge_rudder", (0, RUD_HINGE, FIN_Z0), (0, math.radians(90), 0), root)
    rud = obj("Rudder", rb, hinge, smooth=50)
    # Blue lower-aft triangle across fin and rudder, cut exactly along the diagonal.
    a, b = Vector((0, -3.70, FIN_Z0 - 0.05)), Vector((0, -5.05, FIN_Z0 + 0.62))
    paint_split(fin, a, b)
    paint_split(rud, a, b)


def paint_split(ob, a, b):
    """Bisect a mesh along the line a-b (in the YZ plane) and paint the lower side blue."""
    me = ob.data
    mw = ob.matrix_world
    inv = mw.inverted()
    d = (b - a).normalized()
    n_world = Vector((1, 0, 0)).cross(d).normalized()  # points up-forward of the line
    if n_world.z < 0:
        n_world = -n_world
    co = inv @ a
    no = (inv.to_3x3() @ n_world).normalized()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    if "Paint_Blue" not in [m.name for m in me.materials]:
        me.materials.append(M["blue"])
    blue = [m.name for m in me.materials].index("Paint_Blue")
    for f in bm.faces:
        if (f.calc_center_median() - co).dot(no) < 0:
            f.material_index = blue
    bm.to_mesh(me)
    bm.free()

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
        tube(mb, [foot, front], 0.019, "blue")
        tube(mb, [foot + Vector((0, -0.04, 0)), rear], 0.019, "blue")
        for top, bot in ((front, foot), (rear, foot + Vector((0, -0.04, 0)))):
            mid = bot.lerp(top, 0.6)
            tube(mb, [mid, wing_bottom(side, 1.62, 0.15 if top is front else 0.65)], 0.008, "steel", 6)
    obj("Struts", mb, root, smooth=60)


AXLE_Y, AXLE_Z, AXLE_X = 0.32, -1.705, 0.91
TYRE_R, TYRE_W = 0.255, 0.18
TAIL_AXLE = Vector((0, -4.81, -0.78))


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


def build_gear(root):
    mb = MB()
    for side in (1, -1):
        hub = Vector((side * (AXLE_X - 0.11), AXLE_Y, AXLE_Z))
        top_f = Vector((side * 0.33, 0.52, -1.04))
        tube(mb, [hub, top_f], 0.02, "blue")
        tube(mb, [hub, Vector((side * 0.33, -0.12, -1.04))], 0.02, "blue")
        tube(mb, [hub, Vector((side * 0.02, AXLE_Y, -1.13))], 0.022, "blue")
        tube(mb, [hub.lerp(top_f, 0.62), hub.lerp(top_f, 0.88)], 0.038, "steel", 10)  # bungee housing
    # Tail spring (fixed) up to the steering pivot.
    tube(mb, [(0, -4.42, -0.735), (0, -4.62, -0.72), (0, -4.77, -0.70)], 0.012, "steel", 6)
    obj("Gear", mb, root, smooth=60)

    for side, tag in ((1, "R"), (-1, "L")):
        w = empty("Wheel_" + tag, (side * AXLE_X, AXLE_Y, AXLE_Z), parent=root)
        wb = MB()
        tyre(wb, TYRE_R, TYRE_W, hub_r=0.10)
        wb.v = [tuple(Vector(p) + w.location) for p in wb.v]
        obj("Tyre_" + tag, wb, w, smooth=60)

    steer = empty("Steer_tail", (0, -4.78, -0.70), parent=root)
    fb = MB()
    tube(fb, [(0, -4.78, -0.70), (0.03, -4.80, -0.75), (0.03, -4.81, -0.78)], 0.008, "steel", 6)
    tube(fb, [(0, -4.78, -0.70), (-0.03, -4.80, -0.75), (-0.03, -4.81, -0.78)], 0.008, "steel", 6)
    obj("Tail_fork", fb, steer, smooth=60)
    tw = empty("Wheel_T", tuple(TAIL_AXLE), parent=steer)
    tb = MB()
    tyre(tb, 0.083, 0.04, 16, 8, hub_r=0.03)
    tb.v = [tuple(Vector(p) + TAIL_AXLE) for p in tb.v]
    obj("Tyre_T", tb, tw, smooth=60)


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
            base = Vector((side * (hw - 0.10), y, -0.50))
            lathe(mb, [(0, 0)] + fins + [(0.16, 0.058), (0.16, 0)], "engine", base, "x", 12, side)
            head = base + Vector((side * 0.21, 0, 0))
            hb = [head + Vector((sx * 0.05, sy * 0.065, sz * 0.075)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            vi = [mb.vert(p) for p in hb]
            for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                mb.face([vi[i] for i in f], "engine")
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
    build_engine(root)
    build_prop(root)
    build_registration(root)
    bpy.context.view_layer.update()
    return root


def export():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    lc = bpy.context.view_layer.layer_collection.children["Cub"]
    bpy.context.view_layer.active_layer_collection = lc
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_active_collection=True,
                              export_yup=True, export_apply=True, export_cameras=False, export_lights=False)
    print("exported", OUT, os.path.getsize(OUT), "bytes")


root = build()
faces = sum(len(o.data.polygons) for o in COLL.objects if o.type == "MESH")
print("objects", len(COLL.objects), "faces", faces)
if globals().get("EXPORT", True):
    export()
