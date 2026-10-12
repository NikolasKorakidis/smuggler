class_name StormCell
extends RefCounted
## One thunderstorm cell: grows, matures, dissipates (about 50 minutes) while
## drifting with the wind aloft. Gives the air movement, rain and turbulence
## around it, and how often it makes lightning. Owned by Weather.
##
## Downdraft and outflow: Vicroy's analytic axisymmetric microburst model
## (NASA TM-104053, 1991), the standard simple model for wind-shear studies.
## Updraft under the base while it grows, a gust front running out ahead of
## the downdraft, a rain shaft over the core.

const C1 := -0.22
const C2 := -2.75
const ALPHA := 2.0
## Altitude of the strongest outflow, m (typical 30-100 m).
const ZM := 60.0

var pos := Vector2.ZERO  # centre, world x/z (m)
var velocity := Vector2.ZERO  # drift, m/s
var age := 0.0  # s
var life := 3000.0  # s
var strength := 1.0  # 0.5 weak .. 1.5 severe
## Radius of the strongest outflow (about the size of the rain core), m.
var radius := 1800.0
var base_m := 1200.0  # cloud base above the ground, m

var _lambda := 0.0  # Vicroy scale factor for the current outflow


func _init(at: Vector2, drift: Vector2, power := 1.0, start_age := 0.0, size_m := 1800.0, cloud_base := 1200.0) -> void:
	pos = at
	velocity = drift
	strength = power
	age = start_age
	radius = size_m
	base_m = cloud_base
	life = 2700.0 + 900.0 * clampf(power, 0.0, 1.5) / 1.5


func step(delta: float) -> void:
	age += delta
	pos += velocity * delta
	# Vicroy: peak outflow u_m = (lambda rp / 2)(e^c1 - e^c2) e^(1/(2 alpha)).
	var um := outflow_ms()
	_lambda = 2.0 * um / (radius * (exp(C1) - exp(C2)) * exp(1.0 / (2.0 * ALPHA)))


func finished() -> bool:
	return age >= life


## 0..1 through the life cycle.
func progress() -> float:
	return clampf(age / life, 0.0, 1.0)


## How built-up the cloud is (tower and anvil): grows, holds, slowly fades.
func cloud_k() -> float:
	var t := progress()
	return smoothstep(0.0, 0.3, t) * (1.0 - 0.6 * smoothstep(0.75, 1.0, t))


## Updraft feeding the cell: strongest while it grows.
func updraft_k() -> float:
	var t := progress()
	return smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.35, 0.6, t))


## Downdraft, outflow, heavy rain and lightning: the mature stage.
func mature_k() -> float:
	var t := progress()
	return smoothstep(0.22, 0.38, t) * (1.0 - smoothstep(0.65, 0.9, t))


func rain_k() -> float:
	var t := progress()
	return smoothstep(0.18, 0.35, t) * (1.0 - smoothstep(0.7, 1.0, t))


## Peak microburst outflow speed right now, m/s.
func outflow_ms() -> float:
	return 18.0 * strength * mature_k()


## Rain rate at a world point, mm/h.
func rain_at(p: Vector3) -> float:
	var r := Vector2(p.x, p.z).distance_to(pos)
	return 60.0 * strength * rain_k() * exp(-pow(r / (0.9 * radius), 2.0))


## Extra turbulence (0..1 scale) near and inside the cell.
func turbulence_at(p: Vector3) -> float:
	var r := Vector2(p.x, p.z).distance_to(pos)
	return (0.25 * updraft_k() + 0.7 * mature_k()) * strength * exp(-pow(r / (2.0 * radius), 2.0))


## Lightning flashes per second (all kinds).
func lightning_rate() -> float:
	return 0.08 * strength * mature_k() + 0.01 * updraft_k()


## Air movement from the cell at a world point and height above ground,
## m/s in world axes (y up).
func wind_at(p: Vector3, agl_m: float) -> Vector3:
	var d := Vector2(p.x, p.z) - pos
	var r := maxf(d.length(), 1.0)
	var out_dir := d / r
	var z := maxf(agl_m, 0.0)
	var horizontal := 0.0
	var vertical := 0.0
	# Microburst (Vicroy, eq. 23-24): radial outflow and downdraft.
	if _lambda > 0.0:
		var q := pow((r * r) / (radius * radius), ALPHA)
		var shape := exp((2.0 - q) / (2.0 * ALPHA))
		var zf1 := exp(C1 * z / ZM)
		var zf2 := exp(C2 * z / ZM)
		horizontal += _lambda * r * 0.5 * (zf1 - zf2) * shape
		vertical += -_lambda * ((ZM / C1) * (zf1 - 1.0) - (ZM / C2) * (zf2 - 1.0)) * (1.0 - 0.5 * q) * shape
	# Gust front: the outflow keeps spreading out ahead of the downdraft.
	var front := radius * (1.4 + 2.6 * smoothstep(0.25, 0.7, progress()))
	var surge := 0.5 * outflow_ms() * exp(-pow((r - front) / (0.7 * radius), 2.0)) * (1.0 if r > radius else r / radius)
	horizontal += surge * (exp(C1 * z / ZM) - exp(C2 * z / ZM)) / 0.7386
	# Updraft under the base: at the core while growing, at the flank later.
	var ring := radius * 1.4 * smoothstep(0.2, 0.45, progress())
	vertical += 5.0 * strength * updraft_k() * exp(-pow((r - ring) / (1.2 * radius), 2.0)) * smoothstep(0.0, 0.6 * base_m, z)
	# The drafts are below the cloud base; inside it the turbulence takes over.
	var below := 1.0 - smoothstep(base_m, base_m + 600.0, z)
	return Vector3(out_dir.x * horizontal, vertical, out_dir.y * horizontal) * below
