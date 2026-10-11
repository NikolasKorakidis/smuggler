class_name AircraftSound
extends Resource
## Sound character of one aircraft: engine, propeller, airframe. Read by the
## live synthesiser (audio/aircraft_synth.gd). Every aircraft difference in
## sound lives here, not in code. Defaults = a generic 4-cylinder single.

@export_group("Engine")
@export_range(1, 9) var cylinders := 4
## Rated power, used to turn JSBSim horsepower into engine load (0..1).
@export var rated_hp := 160.0
@export var idle_rpm := 600.0
@export var engine_volume := 1.0
## Resonance of the exhaust pipe / muffler (Hz) and how sharp it is
## (0 = dull thud, 1 = ringing pipe).
@export var exhaust_hz := 140.0
@export_range(0.0, 1.0) var exhaust_ring := 0.4
## High-frequency crack of each exhaust pulse (short stacks = high,
## big muffler = low).
@export_range(0.0, 1.5) var bark := 0.5
## Raspy, noisy edge of the exhaust at high power.
@export_range(0.0, 1.0) var rasp := 0.4
## Length of one exhaust pulse in crank degrees (longer = softer, rounder).
@export var pulse_deg := 45.0
## Airframe / cabin resonance the engine shakes (Hz), and its ring.
@export var body_hz := 110.0
@export_range(0.0, 1.0) var body_ring := 0.4
@export_range(0.0, 2.0) var body_volume := 1.0
## How unequal the cylinders are (worn engine = higher). Gives the lumpy,
## lopey beat under the drone.
@export_range(0.0, 0.6) var cylinder_spread := 0.1
## Firing-to-firing variation (random).
@export_range(0.0, 0.6) var jitter := 0.08
## Baseline chance of a misfire per firing, from wear.
@export_range(0.0, 0.2) var wear := 0.01
## Tappet / valve-train ticking.
@export_range(0.0, 1.0) var valve_clatter := 0.2
## Pops in the exhaust when the throttle is closed at high rpm.
@export_range(0.0, 1.0) var afterfire := 0.3
## Cockpit muffling: low-pass on engine and prop heard from the seat
## (enclosed metal cabin = low, open fabric cabin = high).
@export var cabin_cutoff_hz := 900.0
## Seed for the per-cylinder personality (any number; keep it fixed).
@export var personality_seed := 1

@export_group("Starter")
@export var starter_volume := 1.0
## Starter gear whine pitch (Hz) at 0 rpm and per engine rpm.
@export var starter_hz := 240.0
@export var starter_hz_per_rpm := 1.6

@export_group("Propeller")
@export_range(1, 6) var prop_blades := 2
@export var prop_volume := 1.0
## Difference between the blades (out of track, nicked, worn wooden prop):
## adds a once-per-revolution beat to the buzz.
@export_range(0.0, 0.5) var prop_imbalance := 0.06

@export_group("Airframe")
@export var wind_volume := 1.0
## Wind and leak noise heard from the seat (open, drafty cabin = high).
@export var cabin_wind := 1.0
## Struts and bracing wires singing in the airflow.
@export_range(0.0, 1.0) var whistle := 0.2
@export var whistle_hz_per_kt := 5.0
## Gear and airframe rattle over bumps.
@export_range(0.0, 1.0) var gear_rattle := 0.3
## Angle of attack where buffet starts to be heard.
@export var buffet_alpha_deg := 14.0
@export var stall_horn_hz := 1000.0
