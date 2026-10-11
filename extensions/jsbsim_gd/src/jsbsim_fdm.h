#pragma once

#include <memory>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace JSBSim {
class FGFDMExec;
}

class GodotGroundCallback;

namespace godot {

// Thin wrapper around one JSBSim FGFDMExec instance. Everything aircraft-
// specific lives in the JSBSim XML; this class only exposes the executive.
class JSBSimFDM : public RefCounted {
	GDCLASS(JSBSimFDM, RefCounted)

	std::unique_ptr<JSBSim::FGFDMExec> exec;
	GodotGroundCallback *ground = nullptr; // owned by exec's FGInertial
	String model_name;

protected:
	static void _bind_methods();

public:
	JSBSimFDM();
	~JSBSimFDM();

	// aircraft_dir: absolute path of the folder holding one sub-folder per aircraft.
	bool load_model(const String &aircraft_dir, const String &model);
	bool is_loaded() const;
	String get_model_name() const;

	void set_dt(double dt);
	double get_dt() const;
	double get_sim_time() const;

	bool run_ic();
	bool step();
	int step_n(int count);
	void reset();

	double get_property(const String &name) const;
	void set_property(const String &name, double value);
	bool has_property(const String &name) const;
	PackedStringArray list_properties(const String &filter) const;

	// Terrain source for every ground contact (wheels, structure, AGL).
	// callback(lat_deg: float, lon_deg: float) -> Vector4(elevation_m, normal_east,
	// normal_north, normal_up). An empty Callable restores JSBSim's default: a
	// level ground at position/terrain-elevation-asl-ft.
	void set_ground_callback(const Callable &callback);

	static void set_debug_level(int level);
};

} // namespace godot
