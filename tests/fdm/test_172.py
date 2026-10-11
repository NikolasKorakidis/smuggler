"""172-type (base: JSBSim c172p) vs published C172P figures at 2400 lb max gross.

Reference (C172P spec sheet, sea level, standard day):
  stall 51 KCAS flaps up / 46 KCAS flaps down (power off), climb 700 ft/min,
  max level speed 123 kt, takeoff ground roll 890 ft (flaps 10), O-320 160 hp
  at 2700 rpm, static rpm ~2300-2420 with the fixed-pitch climb prop.
"""

import sim

MODEL = "c172p"
# 1500 lb empty + 370 lb fuel + pilot 180 + front passenger 180 + rear passenger 170 = 2400 lb
MAX_GROSS = dict(fuel_frac=1.0, payload={1: 180, 2: 170})


def test_max_gross_weight():
    s = sim.Sim(MODEL, **MAX_GROSS)
    s.step(0.1)
    assert abs(s["inertia/weight-lbs"] - 2400) < 15


def test_static_rpm():
    rpm, _thrust = sim.static_rpm(MODEL, **MAX_GROSS)
    assert 2280 <= rpm <= 2450, rpm


def test_takeoff_ground_roll_flaps_10():
    roll_ft, liftoff_kcas = sim.takeoff_roll(
        MODEL, rotate_kcas=50, climb_theta=12.0, tail_up_theta=None, flaps=0.33, **MAX_GROSS)
    assert 800 <= roll_ft <= 1000, roll_ft
    assert 48 <= liftoff_kcas <= 58, liftoff_kcas


def test_climb_rate_at_vy():
    fpm = sim.climb_rate(MODEL, vy_kcas=74, **MAX_GROSS)
    assert 640 <= fpm <= 760, fpm


def test_max_level_speed():
    kcas, rpm = sim.level_speed(MODEL, throttle=1.0, start_kcas=110, **MAX_GROSS)
    assert 117 <= kcas <= 128, kcas
    assert rpm <= 2900, rpm


def test_stall_flaps_up():
    kcas, _ = sim.stall_speed(MODEL, start_kcas=70, **MAX_GROSS)
    assert 48 <= kcas <= 54, kcas


def test_stall_full_flaps():
    kcas, _ = sim.stall_speed(MODEL, start_kcas=65, flaps=1.0, **MAX_GROSS)
    assert 43 <= kcas <= 49, kcas


def test_nosewheel_tracks_straight_with_feet_off():
    """Unlike the taildragger, the 172 should roll fairly straight hands-off."""
    s = sim.Sim(MODEL, **MAX_GROSS)
    s.step(2.0)
    s["fcs/throttle-cmd-norm"] = 1.0
    s.step(10.0)
    assert abs(sim.wrap180(s["attitude/psi-deg"])) < 10


def test_flaps_balloon_and_slow_down():
    """Full flaps at 80 KIAS, stick held still: the nose comes up and it slows."""
    s = sim.Sim(MODEL, agl_ft=3000, kcas=80, fuel_frac=0.5, payload={1: 170})
    h_ref, theta, thr = s["position/h-sl-ft"], 1.0, 0.55
    while s.t < 60:  # trim level at 80 kt
        thr = min(1.0, max(0.0, thr + sim.DT * 0.02 * (80 - sim.kcas(s))))
        s["fcs/throttle-cmd-norm"] = thr
        theta += sim.DT * 0.02 * (h_ref - s["position/h-sl-ft"])
        s.hold(theta + 0.05 * (h_ref - s["position/h-sl-ft"]) - 0.2 * s["velocities/h-dot-fps"])
        s.step()
    elevator, v0, th0 = s["fcs/elevator-cmd-norm"], sim.kcas(s), s["attitude/theta-deg"]
    s["fcs/flap-cmd-norm"] = 1.0
    max_theta = th0
    while s.t < 66:
        s["fcs/elevator-cmd-norm"] = elevator
        s.step()
        max_theta = max(max_theta, s["attitude/theta-deg"])
    assert max_theta - th0 > 4.0, max_theta - th0
    assert v0 - sim.kcas(s) > 15.0, v0 - sim.kcas(s)


def test_full_flap_idle_descent_is_steeper():
    def descent(flaps):
        s = sim.Sim(MODEL, agl_ft=4000, kcas=65, **MAX_GROSS)
        s["fcs/flap-cmd-norm"] = flaps
        s.step(1.0)
        return -sim.climb_rate_at(s, 65.0)
    assert descent(1.0) > 1.3 * descent(0.0)
