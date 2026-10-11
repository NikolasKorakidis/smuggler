class_name AircraftDefinition
extends Resource
## One aircraft = one JSBSim model folder + this resource (visuals, sounds).

@export var jsbsim_model := ""
@export var display_name := ""
## Optional imported model, authored in the JSBSim structural frame
## converted to Godot axes (see Geo.struct_to_local). Empty = placeholder.
@export var visual_scene: PackedScene
@export_group("Placeholder")
@export var prop_diameter_m := 1.9
@export var body_color := Color(0.86, 0.82, 0.70)
@export var trim_color := Color(0.55, 0.12, 0.10)
