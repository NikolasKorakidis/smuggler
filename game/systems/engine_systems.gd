class_name EngineSystems
extends Node
## Engine controls and start procedure on top of JSBSim: master, magnetos,
## starter (or hand-propping), primer, mixture, carb heat, fuel selector.
## JSBSim starts an engine whenever it has spark, fuel and rpm, so priming
## and flooding are modelled here by holding back the spark until the
## start would really catch.

signal changed

const MAGNETO_NAMES := ["OFF", "R", "L", "BOTH"]
const PRIME_DECAY := 0.02  # strokes per second, fuel evaporating
const FUEL_LINE_S := 20.0  # engine keeps running this long after fuel OFF
const HAND_PROP_SWING_S := 0.6
const CARB_HEAT_IMPEDANCE := 2.5  # intake impedance multiplier (~80 rpm drop)
## Carburettor ice build-up per second in the worst conditions (tuned against
## the FAA carburettor icing probability chart, SAIB CE-09-35).
const CARB_ICE_RATE := 0.002
const CARB_HEAT_MELT_S := 40.0

var definition: AircraftDefinition
var fdm: FDM

var master := false
var magnetos := 0  # 0 OFF, 1 R, 2 L, 3 BOTH (JSBSim: 1 = left, 2 = right)
var starter := false  # key held in START
var mixture := 1.0
var carb_heat := false
var fuel_selector := 1
var prime := 0.0  # primer strokes in the cylinders
var warmth := 0.0  # 0 cold .. 1 at operating temperature
## Ice in the carburettor venturi, 0..1: chokes the engine; badly iced it quits.
var carb_ice := 0.0
## Rough running from melted ice going through the engine, 0..1.
var melt_rough := 0.0
## Outside air (set by the aircraft): temperature and dew point come from here.
var weather: Weather

var _swing_t := 0.0  # hand-prop swing in progress
var _starter_was_held := false
var _hand_catch := false
var click_starter := false  # ignition key held in START with the mouse
var _spark_allowed := false
var _catch_progress := 0.0
var _catch_needed := 1.0
var _fuel_line_t := FUEL_LINE_S
var _base_impedance := -1.0
var _auto_start_t := -1.0
var _rng := RandomNumberGenerator.new()


func setup(def: AircraftDefinition, model: FDM) -> void:
	definition = def
	fdm = model
	_rng.randomize()


## Cold and dark, or ready to go with the engine running.
func reset(running: bool) -> void:
	master = running and definition.has_master
	magnetos = 3 if running else 0
	starter = false
	mixture = 1.0
	carb_heat = false
	fuel_selector = definition.fuel_default
	prime = 0.0
	warmth = 1.0 if running else 0.0
	carb_ice = 0.0
	melt_rough = 0.0
	_spark_allowed = running
	_catch_progress = 0.0
	_fuel_line_t = FUEL_LINE_S
	_auto_start_t = -1.0
	_swing_t = 0.0
	_base_impedance = fdm.prop_get("propulsion/engine/air-intake-impedance-factor")
	if running:
		fdm.start_engines()
	else:
		fdm.stop_engines()
	apply(0.0)
	changed.emit()


## Starter (or a prop swing) turning the engine right now.
func cranking() -> bool:
	return (starter and powered()) or _swing_t > 0.0


func running() -> bool:
	return fdm.prop_get("propulsion/engine/set-running") > 0.5


func powered() -> bool:
	return master or not definition.has_master


## How well a start would go right now (0 flooded/dry .. 1 good). For sound.
func start_quality() -> float:
	return _start_quality()


## Fuel left in the lines after the supply is cut (1 = fed normally, 0 = dry).
func fuel_line_fraction() -> float:
	return _fuel_line_t / FUEL_LINE_S


# --- controls (from keys, HOTAS buttons and cockpit clicks) -------------------

func set_master(on: bool) -> void:
	if definition.has_master:
		master = on
		changed.emit()


func set_magnetos(pos: int) -> void:
	magnetos = clampi(pos, 0, 3)
	changed.emit()


func set_starter(on: bool) -> void:
	if definition.has_starter:
		starter = on and magnetos == 3
	elif on and _swing_t <= 0.0:
		_swing_t = HAND_PROP_SWING_S  # "Contact!" — one swing of the prop
		if magnetos == 0 and _feeding() and FlightInput.throttle < 0.2:
			prime += 0.7  # pulling it through with the switch off sucks in fuel
		elif magnetos != 0 and _feeding() and not running():
			# Each swing is one chance to catch. A swing is far below JSBSim's
			# own catch rpm, so a good swing starts the engine directly.
			if _rng.randf() < 0.6 * _start_quality():
				_spark_allowed = true
				_hand_catch = true
	changed.emit()


func stroke_primer() -> void:
	if definition.has_primer and _feeding():
		prime += 1.0
		changed.emit()


func set_mixture(v: float) -> void:
	if definition.has_mixture:
		mixture = clampf(v, 0.0, 1.0)
		changed.emit()


func set_carb_heat(on: bool) -> void:
	carb_heat = on
	changed.emit()


func set_fuel_selector(i: int) -> void:
	fuel_selector = clampi(i, 0, definition.fuel_positions.size() - 1)
	changed.emit()


## Simplified start-up assist: does the checklist for you.
func auto_start() -> void:
	if running():
		return
	set_master(true)
	set_fuel_selector(definition.fuel_default)
	set_mixture(1.0)
	set_carb_heat(false)
	if definition.has_primer and warmth < 0.5 and prime < 2.0:
		prime = 3.0
	elif not definition.has_primer and warmth < 0.5 and prime < 2.0:
		prime = 2.5  # as if pulled through
	set_magnetos(3)
	_auto_start_t = 6.0


func shutdown() -> void:
	set_mixture(0.0)


# --- per physics tick, before the FDM steps ----------------------------------

func apply(delta: float) -> void:
	var is_running := running()
	var rpm := fdm.prop_get("propulsion/engine/engine-rpm")

	# Pilot inputs: starter key/button (held), mixture lever (axis or keys).
	var held := FlightInput.starter_held() or click_starter
	if definition.has_starter:
		if _auto_start_t <= 0.0:
			starter = held and magnetos == 3
	elif held and not _starter_was_held:
		set_starter(true)
	_starter_was_held = held
	if definition.has_mixture:
		var axis = FlightInput.mixture_axis()
		if axis != null:
			mixture = axis
		else:
			mixture = clampf(mixture + FlightInput.mixture_key_rate() * delta, 0.0, 1.0)

	# Assisted start: keep cranking until it catches or gives up.
	if _auto_start_t > 0.0:
		_auto_start_t -= delta
		if definition.has_starter:
			starter = not is_running and _auto_start_t > 0.0
		elif not is_running and _swing_t <= 0.0:
			set_starter(true)
		if is_running:
			_auto_start_t = -1.0
			starter = false

	var cranking := (starter and powered()) or _swing_t > 0.0
	_swing_t = maxf(_swing_t - delta, 0.0)

	# Fuel reaches the engine from the selected tanks; the lines hold a little.
	var tanks := _selected_tanks()
	var tank_fuel := 0.0
	for i in tanks:
		tank_fuel += fdm.prop_get("propulsion/tank[%d]/contents-lbs" % i)
	_fuel_line_t = FUEL_LINE_S if (not tanks.is_empty() and tank_fuel > 0.1) else maxf(_fuel_line_t - delta, 0.0)
	var feeding_tanks := tanks if not tanks.is_empty() else (_all_tanks() if _fuel_line_t > 0.0 else PackedInt32Array())
	for i in _all_tanks():
		fdm.prop("propulsion/tank[%d]/priority" % i, 1.0 if i in feeding_tanks else 0.0)

	# Will it catch? Cold engines need priming, too much floods them.
	prime = maxf(prime - PRIME_DECAY * delta, 0.0)
	if is_running:
		_spark_allowed = true
		prime = 0.0
	elif rpm < 50.0 and _swing_t <= 0.0:
		_spark_allowed = false
	if definition.has_starter and not is_running and cranking and magnetos != 0 and _feeding() and mixture > 0.4:
		var q := _start_quality()
		_catch_progress += delta * q
		if _catch_progress >= _catch_needed:
			# Real cranking speed is below JSBSim's own catch rpm, so fire it here.
			_spark_allowed = true
			_hand_catch = true
	elif not cranking:
		_catch_progress = 0.0
		_catch_needed = _rng.randf_range(0.6, 2.0)
	# Cranking a flooded engine with the mixture cut off and throttle open clears it.
	if cranking and mixture < 0.2 and FlightInput.throttle > 0.8:
		prime = maxf(prime - 1.5 * delta, 0.0)
	# Windmilling in the air (not the starter) restarts the engine.
	if not is_running and not cranking and rpm > 500.0 and magnetos != 0 \
			and fdm.prop_get("velocities/vc-kts") > 40.0:
		_spark_allowed = true

	# Warm up while running, cool down slowly when stopped.
	warmth = clampf(warmth + delta * (1.0 / 240.0 if is_running else -1.0 / 1200.0), 0.0, 1.0)

	if _hand_catch:
		_hand_catch = false
		if magnetos != 0 and _feeding() and mixture > 0.4:
			fdm.start_engines()

	_step_carb_ice(delta, rpm, is_running)
	if carb_ice > 0.95 and is_running:
		fdm.stop_engines()  # choked by ice
		_spark_allowed = false
	if carb_ice > 0.85:
		_spark_allowed = false  # won't restart until the ice has melted

	# Hand JSBSim the result. JSBSim magnetos: 1 left, 2 right, 3 both.
	var jsb_mag: int = [0, 2, 1, 3][magnetos]
	fdm.prop("propulsion/magneto_cmd", jsb_mag if _spark_allowed else 0)
	fdm.prop("propulsion/starter_cmd", 1.0 if cranking else 0.0)
	fdm.prop("fcs/mixture-cmd-norm", mixture if definition.has_mixture else 1.0)
	if _base_impedance > 0.0:
		fdm.prop("propulsion/engine/air-intake-impedance-factor",
			_base_impedance * (CARB_HEAT_IMPEDANCE if carb_heat else 1.0) * (1.0 + 2.0 * carb_ice + 6.0 * carb_ice * carb_ice))


# The venturi and evaporating fuel cool the intake air (most at part throttle);
# ice forms when that air is below freezing and below its dew point. Carb heat
# melts it; the water makes the engine run rough for a moment first.
func _step_carb_ice(delta: float, rpm: float, running: bool) -> void:
	if weather == null:
		return
	var h := maxf(fdm.prop_get("position/h-sl-ft") * 0.3048 - weather.field_elevation_m, 0.0)
	var oat := weather.temp_at(h)
	var td := weather.dewpoint_at(h)
	var throttle := clampf(fdm.prop_get("fcs/throttle-pos-norm"), 0.0, 1.0)
	var t_carb := oat + 35.0 if carb_heat else oat - (12.0 + 16.0 * (1.0 - throttle))
	if carb_heat or t_carb > 2.0:
		var melt := delta / CARB_HEAT_MELT_S if carb_heat else delta * (t_carb - 2.0) / 600.0
		var melting := carb_ice > 0.01
		carb_ice = maxf(carb_ice - melt, 0.0)
		# Water from the melting ice goes through the engine: rough for a while.
		melt_rough = move_toward(melt_rough, 0.6 * clampf(carb_ice * 4.0, 0.0, 1.0) if melting else 0.0, delta * (1.5 if melting else 0.4))
	else:
		melt_rough = move_toward(melt_rough, 0.0, delta * 0.4)
	if not carb_heat and t_carb <= 2.0 and running:
		carb_ice = minf(carb_ice + delta * CARB_ICE_RATE * _icing(oat, td, t_carb) * clampf(rpm / 2400.0, 0.2, 1.2), 1.0)


# How readily ice forms (0..~1.3): needs humid air (the chart's main driver),
# an intake below freezing but not so cold the air is dry, and more water in
# warm humid air. Part throttle cools the intake most (glide power is worst).
func _icing(oat: float, td: float, t_carb: float) -> float:
	var rh := exp(17.62 * td / (243.12 + td) - 17.62 * oat / (243.12 + oat))
	var humid := pow(smoothstep(0.4, 1.0, rh), 1.5)
	var freezing := smoothstep(2.0, -2.0, t_carb) * smoothstep(-25.0, -12.0, t_carb)
	var water := clampf(0.5 * exp(0.06 * td), 0.3, 1.3)
	return humid * freezing * water


## How likely carb ice is right now (0 none .. 1 serious), for the dev menu.
func carb_ice_risk() -> float:
	if weather == null:
		return 0.0
	var h := maxf(fdm.prop_get("position/h-sl-ft") * 0.3048 - weather.field_elevation_m, 0.0)
	var oat := weather.temp_at(h)
	var t_carb := oat - (12.0 + 16.0 * (1.0 - clampf(fdm.prop_get("fcs/throttle-pos-norm"), 0.0, 1.0)))
	return clampf(_icing(oat, weather.dewpoint_at(h), t_carb), 0.0, 1.0)


func status_text() -> String:
	var parts := []
	if definition.has_master:
		parts.append("MASTER %s" % ("ON" if master else "OFF"))
	parts.append("MAGS %s" % MAGNETO_NAMES[magnetos])
	parts.append("FUEL %s" % definition.fuel_positions[fuel_selector])
	if definition.has_mixture:
		parts.append("MIX %d%%" % int(mixture * 100))
	parts.append("CARB HEAT %s" % ("ON" if carb_heat else "OFF"))
	if carb_ice > 0.02:
		parts.append("ICE %d%%" % int(carb_ice * 100.0))
	parts.append("PRIME %.1f" % prime)
	parts.append("%s" % ("WARM" if warmth > 0.5 else "COLD"))
	return "  ".join(parts)


func _start_quality() -> float:
	var ideal_min := 2.0 if warmth < 0.5 else 0.0
	var flood := 6.0 if warmth < 0.5 else 3.0
	if prime > flood:
		return 0.0  # flooded
	if prime < ideal_min:
		return 0.05 + 0.3 * prime / ideal_min  # under-primed: slow, may never catch
	return 1.0


func _feeding() -> bool:
	return _fuel_line_t > 0.0


func _selected_tanks() -> PackedInt32Array:
	if fuel_selector < definition.fuel_tanks.size():
		return definition.fuel_tanks[fuel_selector]
	return PackedInt32Array()


func _all_tanks() -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := 0
	while fdm.jsb.has_property("propulsion/tank[%d]/contents-lbs" % i):
		out.append(i)
		i += 1
	return out
