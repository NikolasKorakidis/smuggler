"""Tutorial plane (placeholder: JSBSim J3Cub) vs published J-3C-65 figures.

Reference numbers (approximate, from published J-3C-65 specs):
  stall 38 mph (33 KCAS), max level 87 mph (76 KCAS), climb 450 ft/min,
  static rpm ~2150 with the stock fixed-pitch prop, ground roll ~400 ft.
Bands are deliberately loose; tighten them as Nikolas flies it.
"""

import math

import pytest

import sim

MODEL = "J3Cub"


def test_static_rpm():
    rpm, thrust = sim.static_rpm(MODEL)
    assert 2000 <= rpm <= 2250, rpm
    assert 170 <= thrust <= 260, thrust


def test_takeoff_ground_roll():
    roll_ft, liftoff_kcas = sim.takeoff_roll(MODEL, rotate_kcas=33)
    assert 300 <= roll_ft <= 550, roll_ft
    assert 32 <= liftoff_kcas <= 42, liftoff_kcas


def test_climb_rate_at_vy():
    fpm = sim.climb_rate(MODEL, vy_kcas=39)
    assert 400 <= fpm <= 500, fpm


def test_max_level_speed():
    kcas, rpm = sim.level_speed(MODEL, throttle=1.0)
    assert 70 <= kcas <= 82, kcas
    assert rpm <= 2450, rpm


def test_power_off_stall_speed():
    kcas, _alpha = sim.stall_speed(MODEL)
    assert 30 <= kcas <= 37, kcas


def test_taildragger_swings_without_rudder():
    """Full power with feet off the pedals must not track straight."""
    s = sim.Sim(MODEL)
    s.step(2.0)
    s["fcs/throttle-cmd-norm"] = 1.0
    s.step(15.0)
    assert abs(sim.wrap180(s["attitude/psi-deg"])) > 20


def test_sits_on_gear_at_rest():
    s = sim.Sim(MODEL)
    s["fcs/left-brake-cmd-norm"] = 1.0
    s["fcs/right-brake-cmd-norm"] = 1.0
    s.step(3.0)
    assert s.on_ground
    assert s["attitude/theta-deg"] == pytest.approx(10.7, abs=1.5)  # three-point attitude
    assert math.isclose(s["velocities/vg-fps"], 0.0, abs_tol=0.5)
