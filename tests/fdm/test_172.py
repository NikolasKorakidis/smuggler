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
