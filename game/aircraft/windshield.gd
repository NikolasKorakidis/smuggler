class_name Windshield
extends AnemosGlass
## The windshield: Anemos rain-on-glass, placed from the aircraft definition
## (relative to the pilot's eye).

var aircraft: Aircraft


func setup(ac: Aircraft) -> void:
	aircraft = ac
	var def := ac.definition
	setup_glass(def.windshield_size)
	ac.eyepoint().add_child(self)
	# Quad faces +Z; tilt it back by the rake (top towards the pilot).
	position = def.windshield_center
	rotation = Vector3(deg_to_rad(90.0 - def.windshield_rake_deg), 0.0, 0.0)


func _process(delta: float) -> void:
	if aircraft == null or aircraft.fdm == null or aircraft.world == null or not aircraft.world.get("weather"):
		return
	var tod = aircraft.world.get("time_of_day")
	update_glass(delta, aircraft.world.weather, aircraft.anemos_airspeed(), tod.anemos_exposure() if tod else 1.0)
