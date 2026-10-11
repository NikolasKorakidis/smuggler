class_name AircraftSynth
extends RefCounted
## Live piston-aircraft sound, synthesised per sample (source-filter model).
##
## Engine: one crank-phase accumulator drives firing events, one per cylinder
## in turn. Each firing kicks a short exhaust pulse (with per-cylinder
## strength, random variation and misfires) that rings a fixed-pitch exhaust
## resonance and an airframe resonance, so the timbre stays put while the beat
## follows rpm, like a real engine. Not firing but turning (cranking,
## spool-down) gives soft compression puffs instead. The starter whine and the
## propeller blade-pass buzz ride on the same rpm. Wind, tyres, buffet,
## touchdown thumps and the stall horn share one cheap noise source.
## Pure: no scene access. AircraftAudio sets the inputs every frame.

const RATE := 22050.0
# Mix levels, tuned so full power in the cockpit sits around -14 dBFS RMS.
const ENGINE_GAIN := 0.65
const PROP_GAIN := 0.4
const WIND_GAIN := 0.09
const _INV32 := 1.0 / 2147483648.0

## Ground surfaces: rumble cutoff (Hz), swish (grass), bumps per metre, bump size.
const SURFACES := {
	&"paved": {"rumble_hz": 90.0, "swish": 0.15, "bumps": 0.02, "bump": 0.35},
	&"grass_strip": {"rumble_hz": 140.0, "swish": 1.0, "bumps": 0.35, "bump": 0.6},
	&"grass_rough": {"rumble_hz": 170.0, "swish": 1.3, "bumps": 0.9, "bump": 1.0},
}

var profile: AircraftSound

# --- inputs (set every frame by AircraftAudio) --------------------------------
var rpm := 0.0
var prop_rpm := 0.0
var firing := false  ## combustion happening (not just turning)
var load := 0.0  ## 0 idle .. 1 full power
var roughness := 0.0  ## 0 smooth .. 1 barely running: misfire chance
var cranking := 0.0  ## starter motor engaged, 0..1
var cough_chance := 0.0  ## while cranking: chance a firing comes early
var tip_mach := 0.0  ## propeller helical tip Mach
var thrust := 0.0  ## 0..1, rough share of static thrust
var airspeed_kt := 0.0
var alpha_deg := 0.0
var slip_deg := 0.0
var flaps := 0.0
var ground_speed_kt := 0.0
var on_ground := false
var surface := &"paved"
var horn := false
var view := 0.0  ## 0 outside (chase camera) .. 1 cockpit
var distance_m := 12.0  ## chase camera distance

# --- state ---------------------------------------------------------------------
var _seed := 22222
var _rng := RandomNumberGenerator.new()
var _cyl_gain := PackedFloat32Array()
var _cyl_off := PackedFloat32Array()
var _cyl_weak := PackedFloat32Array()
var _cyl := 0
var _ph := 0.0  # phase within the current firing interval
var _thr := 1.0  # phase of the next firing (uneven per cylinder, wanders)
var _nom := 1.0  # nominal length of this interval
var _half := false
var _env := 0.0  # exhaust pulse envelope
var _xm := 0.0  # exhaust pulse after the muffler
var _dec := 0.99
var _nsh := 0.0  # noise share of the current pulse
var _pf := 0.0  # compression puff envelope (target)
var _pl := 0.0  # puff, smoothed
var _tick := 0.0  # valve tick envelope
var _np := 0.0  # previous noise sample (for high-passed noise)
var _l1 := 0.0
var _b1 := 0.0
var _l2 := 0.0
var _b2 := 0.0
var _c1 := 0.0
var _c2 := 0.0
var _pp := 0.0  # propeller blade phase
var _blade := 0
var _pa := 1.0  # this blade's strength
var _pl1 := 0.0
var _w1 := 0.0
var _w2 := 0.0
var _l3 := 0.0
var _b3 := 0.0
var _r1 := 0.0
var _l4 := 0.0
var _b4 := 0.0
var _rat := 0.0  # rattle / tyre scrub envelope
var _bump_n := 1000
var _sp := 0.0  # starter whine phase
var _hp := 0.0  # horn phase
# Ramped gains (no zipper noise on tonal parts)
var _g_prop := 0.0
var _g_wind := 0.0
var _g_start := 0.0
var _g_horn := 0.0
# Pending one-shots
var _kick := 0.0  # into the airframe resonance (solenoid, stop clunk)
var _thud := 0.0  # into the low "ground" resonance (touchdown, bumps)
var _scrub := 0.0


func _init(sound: AircraftSound = null) -> void:
	profile = sound if sound != null else AircraftSound.new()
	_rng.seed = profile.personality_seed
	var n := maxi(profile.cylinders, 1)
	_cyl_gain.resize(n)
	_cyl_off.resize(n)
	_cyl_weak.resize(n)
	var mean_off := 0.0
	var weak := _rng.randi_range(0, n - 1)
	for i in n:
		_cyl_gain[i] = 1.0 + profile.cylinder_spread * _rng.randf_range(-1.0, 1.0)
		_cyl_off[i] = profile.cylinder_spread * 0.12 * _rng.randf_range(-1.0, 1.0)
		mean_off += _cyl_off[i] / n
		_cyl_weak[i] = 2.2 if i == weak else 0.6
	_cyl_gain[weak] *= 1.0 - 0.6 * profile.cylinder_spread
	for i in n:
		_cyl_off[i] -= mean_off
	_rng.randomize()
	_seed = _rng.randi()


## Touchdown: strength 0..1 from sink rate.
func touchdown(strength: float) -> void:
	_thud += 1.6 * strength
	if surface == &"paved":
		_scrub += 0.5 * strength
	else:
		_scrub += 0.15 * strength
	_rat += profile.gear_rattle * strength


## Mechanical clunk through the airframe (starter solenoid, engine stopping).
func clunk(strength: float) -> void:
	_kick += strength


func render(frames: int, out: PackedVector2Array) -> void:
	if out.size() != frames:
		out.resize(frames)
	if frames <= 0:
		return
	var p := profile
	var inv_n := 1.0 / frames

	# --- engine -----------------------------------------------------------------
	var n_cyl := _cyl_gain.size()
	var inc := rpm / 120.0 * n_cyl / RATE if rpm > 12.0 else 0.0
	var slow := clampf(1.0 - rpm / 450.0, 0.0, 1.0)
	# Crank speed sags into each compression and surges after it: strong when
	# cranking or spooling down, a faint lope at idle.
	var m := 0.33 * slow if not firing else 0.06 * clampf(1.0 - rpm / 1600.0, 0.0, 1.0)
	var tau := clampf(p.pulse_deg / (6.0 * maxf(rpm, 1.0)), 0.0015, 0.008)
	var dec_bang := exp(-1.0 / (RATE * tau))
	var dec_puff := exp(-1.0 / (RATE * clampf(tau * 2.5, 0.006, 0.03)))
	var lf := clampf(load, 0.0, 1.2)
	var amp := 0.45 + 0.55 * lf
	var ns := p.rasp * (0.15 + 0.85 * lf)
	var miss := clampf(roughness, 0.0, 1.0) * 0.8
	var jit := p.jitter + 0.6 * clampf(roughness, 0.0, 1.0)
	# Firing-to-firing timing wander: the lope of a slow idle.
	var lope := (0.5 * p.jitter + 0.25 * clampf(roughness, 0.0, 1.0)) \
			* clampf(1.0 - (rpm - p.idle_rpm) / 1200.0, 0.0, 1.0) if firing else 0.0
	var cough := cough_chance
	var puff := 0.22 + 0.25 * slow
	# Continuous low roar that keeps the resonances ringing between bangs.
	var floor_n := 0.1 * amp if firing else 0.0
	# Muffler: smears each sharp exhaust pulse into a rounder thump.
	var kx := 1.0 - exp(-1.0 / (RATE * (0.0002 + 0.0016 * p.muffler)))
	var clat := p.valve_clatter * (0.35 + 0.65 * clampf(rpm / 2400.0, 0.0, 1.0)) * 0.5
	# Overrun pops: throttle closed, engine pulled round fast by the prop.
	var pop := 0.0
	if firing and lf < 0.12 and rpm > p.idle_rpm * 1.6:
		pop = p.afterfire * 0.012
	var dtick := 0.86
	# Fixed exhaust and body resonances (Chamberlin state-variable filters).
	var f1 := 2.0 * sin(PI * p.exhaust_hz / RATE)
	var q1 := lerpf(1.3, 0.12, p.exhaust_ring)
	var f2 := 2.0 * sin(PI * p.body_hz / RATE)
	var q2 := lerpf(1.3, 0.1, p.body_ring)
	var vin := clampf(view, 0.0, 1.0)
	var vout := 1.0 - vin
	var dist := clampf(12.0 / maxf(distance_m, 1.0), 0.15, 2.0)
	var outside := pow(dist, 0.7)
	var eng_g := ENGINE_GAIN * p.engine_volume * (vin * 1.0 + vout * 1.2 * outside)
	var g_ex := eng_g * q1 * (vin * 0.9 + vout * 1.1)
	var g_cr := eng_g * p.bark * 0.35 * (0.6 + 0.4 * minf(lf, 1.0)) * (vin * 0.35 + vout * 1.0)
	var g_body := eng_g * q2 * p.body_volume * (vin * 1.0 + vout * 0.3)
	var g_clat := eng_g * (vin * 0.8 + vout * 0.6)
	# Cockpit: cabin walls low-pass engine and prop. Outside: air absorbs
	# the highs with distance.
	var cut := lerpf(minf(7000.0, 9000.0 * dist), p.cabin_cutoff_hz, vin)
	var kc := 1.0 - exp(-TAU * cut / RATE)

	# --- propeller ----------------------------------------------------------------
	# The prop is bolted to the crank: blade passes per firing interval.
	var pratio := 2.0 * p.prop_blades / n_cyl * (prop_rpm / rpm if rpm > 1.0 else 1.0)
	var tm := clampf(tip_mach, 0.0, 1.2)
	var kp := clampf(0.04 + 0.9 * tm * tm * tm, 0.04, 0.9)
	var prop_level := PROP_GAIN * p.prop_volume * (tm * tm * 1.6) * (0.45 + 0.55 * clampf(thrust, 0.0, 1.0))
	prop_level *= vin * 0.45 + vout * 1.3 * outside
	# Blade-passage noise: a soft whoosh at low tip speed, a rasp near full power.
	var whoosh := (0.3 + 1.2 * tm * tm) * (0.4 + 0.6 * clampf(thrust, 0.0, 1.0))
	var imbalance := p.prop_imbalance
	var dg_prop := (prop_level - _g_prop) * inv_n

	# --- wind, buffet, whistle --------------------------------------------------------
	var v := maxf(airspeed_kt, 0.0)
	var q := (v / 100.0) * (v / 100.0)
	var wind_level := p.wind_volume * q * (1.0 + 0.6 * flaps + 0.05 * absf(slip_deg)) \
			* (vin * p.cabin_wind + vout * 0.5)
	var wc := clampf(150.0 + 5.0 * v, 150.0, 1200.0)
	var kw := 1.0 - exp(-TAU * wc / RATE)
	# Two-pole low-passed noise, normalised to about unit RMS.
	var wnorm := 1.0 / (0.43 * sqrt(kw / (2.0 - kw)))
	var dg_wind := (WIND_GAIN * wind_level * wnorm - _g_wind) * inv_n
	var g_hiss := WIND_GAIN * wind_level * 0.2 * (vin * 1.0 + vout * 0.3)
	var g_wh := p.whistle * q * 0.5 * clampf((v - 30.0) / 30.0, 0.0, 1.0)
	var f3 := 2.0 * sin(PI * clampf(p.whistle_hz_per_kt * v, 60.0, 2500.0) / RATE)
	var buffet := 0.0
	if not on_ground:
		buffet = smoothstep(p.buffet_alpha_deg - 3.0, p.buffet_alpha_deg + 2.0, alpha_deg) \
				* clampf(q * 4.0, 0.0, 1.0) * 1.5

	# --- ground: rumble, swish, bumps, thuds --------------------------------------------
	var srf: Dictionary = SURFACES.get(surface, SURFACES[&"paved"])
	var gs := maxf(ground_speed_kt, 0.0) if on_ground else 0.0
	var roll := clampf(gs / 40.0, 0.0, 1.0)
	var kr := 1.0 - exp(-TAU * float(srf.rumble_hz) / RATE)
	var g_rum := (roll * 1.4 + buffet) / sqrt(kr) * 0.18
	var g_swish := roll * roll * float(srf.swish) * 0.05
	var bumps_per_sample := float(srf.bumps) * gs * 0.514 / RATE
	var bump_size := float(srf.bump) * (0.3 + 0.7 * roll)
	var rattle := p.gear_rattle
	var f4 := 2.0 * sin(PI * 55.0 / RATE)
	var q4 := 0.45
	var g_low := 0.8
	var drat := 0.9985
	var low_on := roll > 0.001 or buffet > 0.001 or absf(_b4) + absf(_l4) + _rat > 1e-4 \
			or _thud > 0.0 or _scrub > 0.0
	_b4 += _thud
	_thud = 0.0
	_rat += _scrub
	_scrub = 0.0

	# --- starter, horn -------------------------------------------------------------
	# Once the engine catches it outruns the starter pinion: the motor
	# freewheels at its own speed and the whine drops away.
	var start_level := clampf(cranking, 0.0, 1.0) * p.starter_volume * 0.1 * (vin + vout * 0.6) \
			* clampf((700.0 - rpm) / 350.0, 0.3, 1.0)
	var dg_start := (start_level - _g_start) * inv_n
	var sinc := (p.starter_hz + p.starter_hz_per_rpm * minf(rpm, 350.0)) / RATE
	var start_on := start_level > 0.0005 or _g_start > 0.0005
	var horn_level := (0.12 * (vin + vout * 0.15)) if horn else 0.0
	var dg_horn := (horn_level - _g_horn) * inv_n
	var hinc := p.stall_horn_hz / RATE
	var horn_on := horn_level > 0.0 or _g_horn > 0.0005

	_env += _kick * 1.5
	_kick = 0.0

	# Locals for the hot loop.
	var seed := _seed
	var ph := _ph
	var thr := _thr
	var nom := _nom
	var half := _half
	var env := _env
	var xm := _xm
	var dec := _dec
	var nsh := _nsh
	var pf := _pf
	var pl := _pl
	var tick := _tick
	var np := _np
	var l1 := _l1
	var b1 := _b1
	var l2 := _l2
	var b2 := _b2
	var c1 := _c1
	var c2 := _c2
	var pp := _pp
	var blade := _blade
	var pa := _pa
	var pl1 := _pl1
	var w1 := _w1
	var w2 := _w2
	var l3 := _l3
	var b3 := _b3
	var r1 := _r1
	var l4 := _l4
	var b4 := _b4
	var rat := _rat
	var bump_n := _bump_n
	var sp := _sp
	var hp := _hp
	var gp := _g_prop
	var gw := _g_wind
	var gst := _g_start
	var gh := _g_horn
	var cyl := _cyl

	for i in frames:
		seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
		var nz := float(seed) * _INV32 - 1.0
		var hn := nz - np
		np = nz

		# Engine: crank phase and firing events.
		var dph := inc * (1.0 + m * (thr - 2.0 * ph))
		if dph > 0.0:
			ph += dph
			if not half and ph >= 0.5 * thr:
				half = true
				tick += clat
			if ph >= thr:
				# Timing wander is relative to the crank, so it never drifts.
				ph -= nom
				half = false
				cyl += 1
				if cyl >= n_cyl:
					cyl = 0
				nom = 1.0 + _cyl_off[cyl]
				thr = nom + lope * (_rng.randf() - 0.5)
				var fires := firing
				if fires:
					if _rng.randf() < miss * _cyl_weak[cyl]:
						fires = false
				elif cough > 0.0 and _rng.randf() < cough:
					fires = true
				if fires:
					var a := amp * _cyl_gain[cyl] * (1.0 + jit * (_rng.randf() - 0.5))
					env += a
					dec = dec_bang
					nsh = ns
					tick += clat
					if pop > 0.0 and _rng.randf() < pop:
						env += a * 2.5
						nsh = 1.0
				else:
					pf += puff * _cyl_gain[cyl]
		env *= dec
		pf *= dec_puff
		pl += 0.08 * (pf - pl)
		xm += kx * (env * (1.0 + nsh * nz) + nz * floor_n - xm)
		var x := xm + pl * (1.0 + 0.5 * nz)
		l1 += f1 * b1
		var h1 := x - l1 - q1 * b1
		b1 += f1 * h1
		l2 += f2 * b2
		var h2 := x - l2 - q2 * b2
		b2 += f2 * h2
		tick *= dtick
		var e := b1 * g_ex + h1 * g_cr + b2 * g_body + tick * hn * g_clat

		# Propeller: blade-pass buzz, brighter with tip speed, plus whoosh.
		pp += dph * pratio
		if pp >= 1.0:
			# Next blade: blades differ a little (track, nicks), and the air
			# never hits them quite the same twice.
			pp -= 1.0
			blade = 1 - blade
			pa = 1.0 + imbalance * (2 * blade - 1) + 0.12 * (_rng.randf() - 0.5)
		pl1 += kp * ((1.0 - 2.0 * pp) * pa - pl1)
		var w := 1.0 - pp
		gp += dg_prop
		e += (pl1 + w * w * nz * whoosh) * gp

		# Cabin / distance low-pass on engine and prop.
		c1 += kc * (e - c1)
		c2 += kc * (c1 - c2)
		var s := c2

		# Wind roar and leak hiss.
		w1 += kw * (nz - w1)
		w2 += kw * (w1 - w2)
		gw += dg_wind
		s += w2 * gw + (nz - w1) * g_hiss
		if g_wh > 0.0:
			l3 += f3 * b3
			var h3 := nz - l3 - 0.06 * b3
			b3 += f3 * h3
			s += b3 * g_wh * 0.09

		# Ground: tyre rumble, grass swish, bumps, rattle, thuds, buffet.
		if low_on:
			r1 += kr * (nz - r1)
			var lin := r1 * g_rum
			if bumps_per_sample > 0.0:
				bump_n -= 1
				if bump_n <= 0:
					var bsz := bump_size * (0.3 + _rng.randf())
					b4 += bsz * 0.6
					rat += rattle * bsz * 0.5
					bump_n = mini(int((0.4 + _rng.randf() * 1.2) / bumps_per_sample), int(RATE))
			l4 += f4 * b4
			var h4 := lin - l4 - q4 * b4
			b4 += f4 * h4
			s += b4 * g_low + (nz - r1) * g_swish + rat * hn * 0.37
			rat *= drat

		# Starter: gear whine following crank speed, brush noise.
		if start_on:
			sp += sinc * (1.0 + 1.5 * m * (thr - 2.0 * ph))
			if sp >= 1.0:
				sp -= 1.0
			gst += dg_start
			s += (absf(2.0 * sp - 1.0) * 2.0 - 1.0 + 0.3 * hn) * gst

		# Stall horn: reedy tone.
		if horn_on:
			hp += hinc
			if hp >= 1.0:
				hp -= 1.0
			gh += dg_horn
			s += (absf(4.0 * hp - 2.0) - 1.0 + 0.3 * (2.0 * hp - 1.0)) * gh

		# Soft limiter, transparent below 0.6.
		if s > 0.6:
			var t := s - 0.6
			s = 0.6 + t / (1.0 + 2.5 * t)
		elif s < -0.6:
			var t := -0.6 - s
			s = -0.6 - t / (1.0 + 2.5 * t)
		out[i] = Vector2(s, s)

	_seed = seed
	_ph = ph
	_thr = thr
	_nom = nom
	_half = half
	_env = env
	_xm = xm
	_dec = dec
	_nsh = nsh
	_pf = pf
	_pl = pl
	_tick = tick
	_np = np
	_l1 = l1
	_b1 = b1
	_l2 = l2
	_b2 = b2
	_c1 = c1
	_c2 = c2
	_pp = pp
	_blade = blade
	_pa = pa
	_pl1 = pl1
	_w1 = w1
	_w2 = w2
	_l3 = l3
	_b3 = b3
	_r1 = r1
	_l4 = l4
	_b4 = b4
	_rat = rat
	_bump_n = bump_n
	_sp = sp
	_hp = hp
	_g_prop = prop_level
	_g_wind = gw
	_g_start = start_level
	_g_horn = horn_level
	_cyl = cyl
