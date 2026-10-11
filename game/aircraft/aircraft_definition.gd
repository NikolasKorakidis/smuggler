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
## Stall warning horn sounds above this angle of attack. 0 = no horn.
@export var stall_warning_alpha_deg := 0.0
## Flap command (0..1) at each notch, first = up. Empty = no flaps.
@export var flap_detents: PackedFloat32Array = []
@export_group("Placeholder")
@export var prop_diameter_m := 1.9
@export var body_color := Color(0.86, 0.82, 0.70)
@export var trim_color := Color(0.55, 0.12, 0.10)
