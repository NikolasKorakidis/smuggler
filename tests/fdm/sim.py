"""Headless JSBSim harness shared by the flight-model tests.

Loads aircraft from game/aircraft (the same files the game uses) and flies
simple test manoeuvres with a scripted pilot.
"""

import math
import os

import jsbsim

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
AIRCRAFT_DIR = os.path.join(ROOT, "game", "aircraft")
DT = 1.0 / 120.0
FT = 0.3048


def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))


def wrap180(deg):
    return (deg + 180.0) % 360.0 - 180.0


class Sim:
    def __init__(self, model, agl_ft=0.0, kcas=0.0, psi_deg=0.0, fuel_frac=None):
        self.fdm = jsbsim.FGFDMExec(root_dir=AIRCRAFT_DIR)
        self.fdm.set_debug_level(0)
        ok = self.fdm.load_model_with_paths(
            model,
            AIRCRAFT_DIR,
            os.path.join(AIRCRAFT_DIR, "engine"),
            os.path.join(AIRCRAFT_DIR, "systems"),
        )
        assert ok, f"failed to load {model}"
        self.fdm.set_dt(DT)
        self["ic/terrain-elevation-ft"] = 0.0
        self["ic/h-agl-ft"] = agl_ft
        self["ic/vc-kts"] = kcas
        self["ic/psi-true-deg"] = psi_deg
        self.psi_ref = psi_deg
        assert self.fdm.run_ic()
        if fuel_frac is not None:
            cap = self["propulsion/tank/capacity-lbs"]
            self["propulsion/tank/contents-lbs"] = cap * fuel_frac
        self["propulsion/magneto_cmd"] = 3
        self["propulsion/set-running"] = -1
        self["fcs/mixture-cmd-norm"] = 1.0
        self["fcs/throttle-cmd-norm"] = 0.0
        self.theta_target = None

    def __getitem__(self, key):
        return self.fdm[key]

    def __setitem__(self, key, value):
        self.fdm[key] = value

    @property
    def t(self):
        return self.fdm.get_sim_time()

    @property
    def on_ground(self):
        return any(self[f"gear/unit[{i}]/WOW"] > 0 for i in range(3))

    # --- controls (same conventions as the game input layer) ---------------
    def pedals(self, right):
        """right in [-1, 1], +1 = full right pedal (nose right)."""
        self["fcs/rudder-cmd-norm"] = -right
        self["fcs/steer-cmd-norm"] = right

    def stick(self, pitch_back, roll_right):
        """pitch_back +1 = full aft stick (nose up)."""
        self["fcs/elevator-cmd-norm"] = -pitch_back
        self["fcs/aileron-cmd-norm"] = roll_right

    # --- scripted pilot ----------------------------------------------------
    def hold(self, theta_deg=None, kp=0.08, kd=0.06):
        psi_err = wrap180(self.psi_ref - self["attitude/psi-deg"])
        r = math.degrees(self["velocities/r-rad_sec"])
        self.pedals(clamp(0.12 * psi_err - 0.08 * r))
        phi = self["attitude/phi-deg"]
        p = math.degrees(self["velocities/p-rad_sec"])
        roll = clamp(-0.05 * phi - 0.02 * p + 0.01 * psi_err)
        pitch = 0.0
        if theta_deg is not None:
            q = math.degrees(self["velocities/q-rad_sec"])
            pitch = clamp(kp * (theta_deg - self["attitude/theta-deg"]) - kd * q)
        self.stick(pitch, roll)

    def step(self, seconds=DT):
        n = max(1, int(round(seconds / DT)))
        for _ in range(n):
            self.fdm.run()


def kcas(sim):
    return sim["velocities/vc-kts"]


def static_rpm(model):
    s = Sim(model)
    s["fcs/throttle-cmd-norm"] = 1.0
    s["fcs/left-brake-cmd-norm"] = 1.0
    s["fcs/right-brake-cmd-norm"] = 1.0
    s.step(5.0)
    return s["propulsion/engine/engine-rpm"], s["propulsion/engine/thrust-lbs"]


def takeoff_roll(model, rotate_kcas, climb_theta=8.0, tail_up_theta=1.0):
    """Full-power takeoff from a standstill on a paved surface, no wind.
    Returns (ground roll in ft, liftoff KCAS)."""
    s = Sim(model)
    s.step(2.0)  # settle on the gear
    x0 = s["position/distance-from-start-mag-mt"]
    s["fcs/throttle-cmd-norm"] = 1.0
    airborne_since = None
    while s.t < 90:
        v = kcas(s)
        if v < 15:
            s.hold(None)
        elif v < rotate_kcas:
            s.hold(tail_up_theta)
        else:
            s.hold(climb_theta)
        s.step()
        if not s.on_ground:
            if airborne_since is None:
                airborne_since = (s.t, s["position/distance-from-start-mag-mt"], v)
            elif s.t - airborne_since[0] > 1.0:
                return (airborne_since[1] - x0) / FT, airborne_since[2]
        else:
            airborne_since = None
    raise AssertionError("no liftoff within 90 s")


def _speed_hold_theta(s, target_kcas, theta_trim, k=0.6):
    return theta_trim + k * (kcas(s) - target_kcas)


def climb_rate(model, vy_kcas, alt_ft=1000.0, settle=20.0, measure=30.0):
    """Full-power climb at vy. Returns average climb rate in ft/min."""
    s = Sim(model, agl_ft=alt_ft, kcas=vy_kcas)
    s["fcs/throttle-cmd-norm"] = 1.0
    theta = 6.0
    t_end = settle + measure
    h0 = None
    while s.t < t_end:
        # integrate a slow trim term so the speed error settles out
        theta += 0.05 * DT * (kcas(s) - vy_kcas)
        s.hold(_speed_hold_theta(s, vy_kcas, theta))
        s.step()
        if h0 is None and s.t >= settle:
            h0, t0 = s["position/h-sl-ft"], s.t
    return (s["position/h-sl-ft"] - h0) / (s.t - t0) * 60.0


def level_speed(model, throttle=1.0, alt_ft=1000.0, start_kcas=60.0, seconds=150.0):
    """Altitude-hold flight at fixed throttle. Returns steady KCAS and RPM."""
    s = Sim(model, agl_ft=alt_ft, kcas=start_kcas)
    s["fcs/throttle-cmd-norm"] = throttle
    h_ref = s["position/h-sl-ft"]
    theta = 2.0
    while s.t < seconds:
        h_err = h_ref - s["position/h-sl-ft"]
        hdot = s["velocities/h-dot-fps"]
        theta += DT * 0.02 * h_err
        s.hold(theta + 0.05 * h_err - 0.2 * hdot)
        s.step()
    return kcas(s), s["propulsion/engine/engine-rpm"]


def stall_speed(model, alt_ft=3000.0, ramp_s=40.0):
    """Power-off, wings-level stall: ease the stick back from neutral to the
    aft stop over ramp_s seconds. Returns the lowest KCAS reached, plus the
    angle of attack at that moment."""
    s = Sim(model, agl_ft=alt_ft, kcas=55.0)
    s["fcs/throttle-cmd-norm"] = 0.0
    min_v, alpha_at_min = 1e9, None
    t0 = s.t
    while s.t - t0 < ramp_s + 10.0:
        back = clamp((s.t - t0) / ramp_s, 0.0, 1.0)
        s.hold(None)
        s.stick(back, s["fcs/aileron-cmd-norm"])
        s.step()
        v = kcas(s)
        if v < min_v:
            min_v, alpha_at_min = v, s["aero/alpha-deg"]
    return min_v, alpha_at_min
