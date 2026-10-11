#include "jsbsim_fdm.h"

#include <cmath>
#include <exception>

#include <FGFDMExec.h>
#include <input_output/FGGroundCallback.h>
#include <input_output/FGPropertyManager.h>
#include <math/FGColumnVector3.h>
#include <math/FGLocation.h>
#include <models/FGInertial.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector4.hpp>

using namespace godot;

namespace {

std::string to_std(const String &s) {
	return std::string(s.utf8().get_data());
}

} // namespace

// Ground contact source. Without a Callable it is identical to JSBSim's
// FGDefaultGroundCallback (level ground at the set terrain elevation). With
// one, the game world supplies elevation and surface normal per query, so
// every wheel finds the real ground under it, slopes included.
class GodotGroundCallback : public JSBSim::FGGroundCallback {
	double a, b; // planet semi-axes, ft
	double fallback_elevation_ft = 0.0;

public:
	godot::Callable callback;

	GodotGroundCallback(double semimajor, double semiminor) :
			a(semimajor), b(semiminor) {}

	using FGGroundCallback::GetAGLevel;

	double GetAGLevel(double t, const JSBSim::FGLocation &location, JSBSim::FGLocation &contact,
			JSBSim::FGColumnVector3 &normal, JSBSim::FGColumnVector3 &v,
			JSBSim::FGColumnVector3 &w) const override {
		v.InitMatrix();
		w.InitMatrix();
		JSBSim::FGLocation l = location;
		l.SetEllipse(a, b);
		const double lat = l.GetGeodLatitudeRad();
		const double lon = l.GetLongitude();
		const double slat = sin(lat), clat = cos(lat), slon = sin(lon), clon = cos(lon);
		// Local east / north / up unit vectors in ECEF.
		const JSBSim::FGColumnVector3 east(-slon, clon, 0.0);
		const JSBSim::FGColumnVector3 north(-slat * clon, -slat * slon, clat);
		const JSBSim::FGColumnVector3 up(clat * clon, clat * slon, slat);

		double elevation_ft = fallback_elevation_ft;
		normal = up;
		if (callback.is_valid()) {
			const godot::Variant r = callback.call(godot::Math::rad_to_deg(lat), godot::Math::rad_to_deg(lon));
			if (r.get_type() == godot::Variant::VECTOR4) {
				const godot::Vector4 g = r;
				elevation_ft = g.x / 0.3048;
				JSBSim::FGColumnVector3 n = east * g.y + north * g.z + up * g.w;
				const double len = n.Magnitude();
				if (len > 1e-6 && g.w > 0.0) {
					normal = n / len;
				}
			}
		}
		contact.SetEllipse(a, b);
		contact.SetPositionGeodetic(lon, lat, elevation_ft);
		// Vertical height above the ground, as JSBSim's gear model expects.
		return l.GetGeodAltitude() - elevation_ft;
	}

	void SetTerrainElevation(double h) override { fallback_elevation_ft = h; }
	void SetEllipse(double semimajor, double semiminor) override {
		a = semimajor;
		b = semiminor;
	}
};

void JSBSimFDM::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_model", "aircraft_dir", "model"), &JSBSimFDM::load_model);
	ClassDB::bind_method(D_METHOD("is_loaded"), &JSBSimFDM::is_loaded);
	ClassDB::bind_method(D_METHOD("get_model_name"), &JSBSimFDM::get_model_name);
	ClassDB::bind_method(D_METHOD("set_dt", "dt"), &JSBSimFDM::set_dt);
	ClassDB::bind_method(D_METHOD("get_dt"), &JSBSimFDM::get_dt);
	ClassDB::bind_method(D_METHOD("get_sim_time"), &JSBSimFDM::get_sim_time);
	ClassDB::bind_method(D_METHOD("run_ic"), &JSBSimFDM::run_ic);
	ClassDB::bind_method(D_METHOD("step"), &JSBSimFDM::step);
	ClassDB::bind_method(D_METHOD("step_n", "count"), &JSBSimFDM::step_n);
	ClassDB::bind_method(D_METHOD("reset"), &JSBSimFDM::reset);
	ClassDB::bind_method(D_METHOD("get_property", "name"), &JSBSimFDM::get_property);
	ClassDB::bind_method(D_METHOD("set_property", "name", "value"), &JSBSimFDM::set_property);
	ClassDB::bind_method(D_METHOD("has_property", "name"), &JSBSimFDM::has_property);
	ClassDB::bind_method(D_METHOD("list_properties", "filter"), &JSBSimFDM::list_properties, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("set_ground_callback", "callback"), &JSBSimFDM::set_ground_callback);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("set_debug_level", "level"), &JSBSimFDM::set_debug_level);
}

JSBSimFDM::JSBSimFDM() {}

JSBSimFDM::~JSBSimFDM() {
	// JSBSim reads tied properties (AGL, terrain elevation) while tearing
	// down; don't let that call back into a script that is being freed.
	if (ground) {
		ground->callback = Callable();
	}
}

void JSBSimFDM::set_debug_level(int level) {
	JSBSim::FGJSBBase::debug_lvl = level;
}

bool JSBSimFDM::load_model(const String &aircraft_dir, const String &model) {
	try {
		ground = nullptr;
		exec = std::make_unique<JSBSim::FGFDMExec>();
		const std::string dir = to_std(aircraft_dir);
		exec->SetRootDir(SGPath::fromUtf8(dir));
		const bool ok = exec->LoadModel(SGPath::fromUtf8(dir), SGPath::fromUtf8(dir + "/engine"),
				SGPath::fromUtf8(dir + "/systems"), to_std(model));
		if (!ok) {
			UtilityFunctions::push_error("JSBSim: failed to load model '", model, "' from ", aircraft_dir);
			exec.reset();
			return false;
		}
		model_name = model;
		auto inertial = exec->GetInertial();
		ground = new GodotGroundCallback(inertial->GetSemimajor(), inertial->GetSemiminor());
		inertial->SetGroundCallback(ground); // takes ownership
		return true;
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("JSBSim: exception loading '", model, "': ", e.what());
	} catch (...) {
		UtilityFunctions::push_error("JSBSim: unknown exception loading '", model, "'");
	}
	ground = nullptr;
	exec.reset();
	return false;
}

bool JSBSimFDM::is_loaded() const {
	return exec != nullptr;
}

String JSBSimFDM::get_model_name() const {
	return model_name;
}

void JSBSimFDM::set_dt(double dt) {
	ERR_FAIL_COND(!exec);
	exec->Setdt(dt);
}

double JSBSimFDM::get_dt() const {
	ERR_FAIL_COND_V(!exec, 0.0);
	return exec->GetDeltaT();
}

double JSBSimFDM::get_sim_time() const {
	ERR_FAIL_COND_V(!exec, 0.0);
	return exec->GetSimTime();
}

bool JSBSimFDM::run_ic() {
	ERR_FAIL_COND_V(!exec, false);
	try {
		return exec->RunIC();
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("JSBSim: RunIC failed: ", e.what());
	}
	return false;
}

bool JSBSimFDM::step() {
	ERR_FAIL_COND_V(!exec, false);
	try {
		return exec->Run();
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("JSBSim: Run failed: ", e.what());
	}
	return false;
}

int JSBSimFDM::step_n(int count) {
	int done = 0;
	while (done < count && step()) {
		done++;
	}
	return done;
}

void JSBSimFDM::reset() {
	ERR_FAIL_COND(!exec);
	try {
		exec->ResetToInitialConditions(0);
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("JSBSim: reset failed: ", e.what());
	}
}

double JSBSimFDM::get_property(const String &name) const {
	ERR_FAIL_COND_V(!exec, 0.0);
	return exec->GetPropertyValue(to_std(name));
}

void JSBSimFDM::set_property(const String &name, double value) {
	ERR_FAIL_COND(!exec);
	exec->SetPropertyValue(to_std(name), value);
}

bool JSBSimFDM::has_property(const String &name) const {
	ERR_FAIL_COND_V(!exec, false);
	return exec->GetPropertyManager()->HasNode(to_std(name));
}

PackedStringArray JSBSimFDM::list_properties(const String &filter) const {
	PackedStringArray out;
	ERR_FAIL_COND_V(!exec, out);
	for (const std::string &line : exec->GetPropertyCatalog()) {
		String s = String::utf8(line.c_str());
		if (filter.is_empty() || s.contains(filter)) {
			out.push_back(s);
		}
	}
	return out;
}

void JSBSimFDM::set_ground_callback(const Callable &callback) {
	ERR_FAIL_COND(!exec || !ground);
	ground->callback = callback;
}
