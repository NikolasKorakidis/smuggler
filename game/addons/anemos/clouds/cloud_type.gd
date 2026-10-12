# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
class_name AnemosCloudType
extends Resource
## One kind of cloud for the cloud engine (clouds.glsl): how it fills its
## layer and how it looks. The library lives in world/clouds/types/
## (made by dev/make_cloud_types.gd); weather and the dev menu pick from it.

@export var display_name := ""
## Density from the bottom (0) to the top (1) of the layer.
@export var profile: Curve
## Typical depth of the layer (m), when the weather doesn't say.
@export var default_depth := 800.0
## 1 = separate heaps (cumulus cells), 0 = a continuous sheet.
@export_range(0.0, 1.0) var heaps := 1.0
## How sharp the cloud edges are against clear air (smaller = crisper).
@export var softness := 0.07
## How much fine detail eats into the edges (wisps and billows).
@export var erosion := 0.45
## How much the sides bulge out (domain warp, m).
@export var billow := 450.0
## Heaps get narrower towards the top (domes, towers).
@export var narrowing := 0.14
@export var density := 1.0
## Light extinction inside (1/m): ~0.07 cumulus (30-50 m visibility), ~0.03 stratus.
@export var extinction := 0.06
## Base height wobble (m) and top height wobble for sheets (m).
@export var base_wobble := 70.0
@export var top_wobble := 0.0
## Sheets thicker and thinner in patches (darker/lighter underneath), 0..1.
@export var patchiness := 0.0
## Size of the billows: 1 = default noise scales.
@export var scale := 1.0


func packed() -> Array[Vector4]:
	return [Vector4(softness, erosion, billow, density),
		Vector4(extinction, heaps, narrowing, base_wobble),
		Vector4(top_wobble, patchiness, scale, 0.0)]
