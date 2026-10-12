# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
extends SceneTree
## Writes the cloud type library (world/clouds/types/*.tres):
## godot --headless --path game -s res://addons/anemos/tools/make_cloud_types.gd
## Profile points: (height in layer 0..1, density 0..1).

const TYPES := {
	"cumulus_humilis": {"name": "Cumulus humilis (fair-weather)", "depth": 500.0, "heaps": 1.0, "softness": 0.06, "erosion": 0.45,
		"billow": 350.0, "narrowing": 0.18, "density": 0.9, "extinction": 0.06, "base_wobble": 40.0, "scale": 0.8,
		"profile": [[0.0, 0.0], [0.06, 1.0], [0.3, 1.0], [0.75, 0.45], [1.0, 0.0]]},
	"cumulus_mediocris": {"name": "Cumulus mediocris", "depth": 1200.0, "heaps": 1.0, "softness": 0.06, "erosion": 0.5,
		"billow": 450.0, "narrowing": 0.15, "density": 1.0, "extinction": 0.07, "base_wobble": 60.0, "scale": 1.0,
		"profile": [[0.0, 0.0], [0.05, 1.0], [0.35, 1.0], [0.8, 0.5], [1.0, 0.0]]},
	"cumulus_congestus": {"name": "Cumulus congestus (towering)", "depth": 2600.0, "heaps": 1.0, "softness": 0.05, "erosion": 0.55,
		"billow": 600.0, "narrowing": 0.2, "density": 1.15, "extinction": 0.08, "base_wobble": 80.0, "scale": 1.3,
		"profile": [[0.0, 0.0], [0.04, 1.0], [0.55, 1.0], [0.88, 0.6], [1.0, 0.0]]},
	"cumulonimbus": {"name": "Cumulonimbus (storm)", "depth": 9500.0, "heaps": 1.0, "softness": 0.05, "erosion": 0.5,
		"billow": 700.0, "narrowing": 0.1, "density": 2.5, "extinction": 0.09, "base_wobble": 30.0, "scale": 1.6,
		"profile": [[0.0, 0.0], [0.012, 1.0], [0.8, 1.0], [0.95, 0.6], [1.0, 0.0]]},
	"stratocumulus": {"name": "Stratocumulus", "depth": 600.0, "heaps": 0.5, "softness": 0.08, "erosion": 0.35,
		"billow": 300.0, "narrowing": 0.06, "density": 0.85, "extinction": 0.05, "base_wobble": 90.0, "top_wobble": 160.0,
		"patchiness": 0.5, "scale": 0.9, "profile": [[0.0, 0.0], [0.1, 1.0], [0.6, 1.0], [1.0, 0.0]]},
	"stratus": {"name": "Stratus (low grey sheet)", "depth": 500.0, "heaps": 0.0, "softness": 0.1, "erosion": 0.15,
		"billow": 150.0, "narrowing": 0.0, "density": 0.8, "extinction": 0.035, "base_wobble": 110.0, "top_wobble": 220.0,
		"patchiness": 0.7, "scale": 1.0, "profile": [[0.0, 0.0], [0.12, 1.0], [0.55, 1.0], [1.0, 0.0]]},
	"nimbostratus": {"name": "Nimbostratus (rain cloud)", "depth": 2500.0, "heaps": 0.1, "softness": 0.1, "erosion": 0.2,
		"billow": 250.0, "narrowing": 0.0, "density": 1.1, "extinction": 0.045, "base_wobble": 150.0, "top_wobble": 300.0,
		"patchiness": 0.6, "scale": 1.4, "profile": [[0.0, 0.0], [0.08, 1.0], [0.7, 1.0], [1.0, 0.0]]},
	"altocumulus": {"name": "Altocumulus (mid-level heaps)", "depth": 400.0, "heaps": 0.8, "softness": 0.07, "erosion": 0.5,
		"billow": 250.0, "narrowing": 0.1, "density": 0.7, "extinction": 0.04, "base_wobble": 50.0, "top_wobble": 60.0,
		"patchiness": 0.3, "scale": 0.55, "profile": [[0.0, 0.0], [0.15, 1.0], [0.5, 1.0], [1.0, 0.0]]},
	"altostratus": {"name": "Altostratus (mid-level sheet)", "depth": 900.0, "heaps": 0.0, "softness": 0.12, "erosion": 0.15,
		"billow": 200.0, "narrowing": 0.0, "density": 0.6, "extinction": 0.025, "base_wobble": 120.0, "top_wobble": 150.0,
		"patchiness": 0.6, "scale": 1.2, "profile": [[0.0, 0.0], [0.15, 1.0], [0.6, 1.0], [1.0, 0.0]]},
}


func _init() -> void:
	for id in TYPES:
		var d: Dictionary = TYPES[id]
		var t := AnemosCloudType.new()
		t.display_name = d.name
		t.default_depth = d.depth
		t.heaps = d.heaps
		t.softness = d.softness
		t.erosion = d.erosion
		t.billow = d.billow
		t.narrowing = d.narrowing
		t.density = d.density
		t.extinction = d.extinction
		t.base_wobble = d.base_wobble
		t.top_wobble = d.get("top_wobble", 0.0)
		t.patchiness = d.get("patchiness", 0.0)
		t.scale = d.scale
		var c := Curve.new()
		for pt in d.profile:
			c.add_point(Vector2(pt[0], pt[1]))
		t.profile = c
		var path := "res://addons/anemos/clouds/types/%s.tres" % id
		var err := ResourceSaver.save(t, path)
		print(path, " ", "ok" if err == OK else "ERROR %d" % err)
	quit()
