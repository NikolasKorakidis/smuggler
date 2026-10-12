# Anemos - weather and cloud system for Godot.
# Copyright (c) 2026 Nikolas Korakidis. All rights reserved. See addons/anemos/LICENSE.md.
@tool
extends EditorPlugin
## Registers the global shader parameters Anemos publishes (so ground
## shaders using anemos_ground.gdshaderinc compile) when the plugin is enabled.

const GLOBALS := {
	"anemos_wetness": {"type": "float", "value": 0.0},
	"anemos_cloud_shadow": {"type": "sampler2D", "value": ""},
	"anemos_cloud_shadow_rect": {"type": "vec4", "value": Vector4(0, 0, 1, -1e6)},
	"anemos_sun_direction": {"type": "vec3", "value": Vector3.UP},
}


func _enable_plugin() -> void:
	var changed := false
	for k in GLOBALS:
		var key: String = "shader_globals/" + k
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, GLOBALS[k])
			changed = true
	if changed:
		ProjectSettings.save()
