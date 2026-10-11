class_name AircraftDefinition
extends Resource
## One aircraft = one JSBSim model folder + this resource (visuals, sounds).

@export var jsbsim_model := ""
@export var display_name := ""
## Optional imported model, authored in the JSBSim structural frame
## converted to Godot axes (see Geo.struct_to_local). Empty = placeholder.
@export var visual_scene: PackedScene
## Instrument panel, authored relative to the pilot's eye (origin = eyepoint,
## looking down -Z). Empty = plain placeholder panel.
@export var panel_scene: PackedScene
## Default cockpit camera pitch, degrees (negative = looking down at the panel).
@export var cockpit_look_pitch_deg := -4.0
## Start-up checklist (text file, see aircraft/<model>/checklist.txt).
@export_file("*.txt") var checklist := ""
@export_group("Engine")
## Battery master switch; without one nothing is electric (Cub).
@export var has_master := true
## Electric starter; without one the prop is swung by hand.
@export var has_starter := true
@export var has_primer := true
@export var has_mixture := true
## Fuel selector positions and the JSBSim tanks each one feeds.
@export var fuel_positions: PackedStringArray = ["OFF", "ON"]
@export var fuel_tanks: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array([0])]
@export var fuel_default := 1
@export_group("")
## Stall warning horn sounds above this angle of attack. 0 = no horn.
@export var stall_warning_alpha_deg := 0.0
## Flap command (0..1) at each notch, first = up. Empty = no flaps.
@export var flap_detents: PackedFloat32Array = []
## Engine, propeller and airframe sound character. Empty = generic.
@export var sound: AircraftSound
@export_group("Placeholder")
@export var prop_diameter_m := 1.9
@export var body_color := Color(0.86, 0.82, 0.70)
@export var trim_color := Color(0.55, 0.12, 0.10)
