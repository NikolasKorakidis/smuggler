#include "jsbsim_fdm.h"

#include <exception>

#include <FGFDMExec.h>
#include <input_output/FGPropertyManager.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace {

std::string to_std(const String &s) {
	return std::string(s.utf8().get_data());
}

} // namespace

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
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("set_debug_level", "level"), &JSBSimFDM::set_debug_level);
}

JSBSimFDM::JSBSimFDM() {}

JSBSimFDM::~JSBSimFDM() {}

void JSBSimFDM::set_debug_level(int level) {
	JSBSim::FGJSBBase::debug_lvl = level;
}

bool JSBSimFDM::load_model(const String &aircraft_dir, const String &model) {
	try {
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
		return true;
	} catch (const std::exception &e) {
		UtilityFunctions::push_error("JSBSim: exception loading '", model, "': ", e.what());
	} catch (...) {
		UtilityFunctions::push_error("JSBSim: unknown exception loading '", model, "'");
	}
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
