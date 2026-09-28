"""The sword's animations (see anims.py: POSING BY DIRECTION). Space: the
character's own - x right, y up, -z forward (the enemy).

THE FEEL (a tennis swing, not a poke): each swing travels round a SWING
PLANE, the way a real slash or a forehand does. The blade's angle round
that plane (phi: 0 at the hit, pointing at the enemy; minus before, plus
after) follows a timing curve -
  * a quick coil back, held for a heartbeat (you can see it coming),
  * the whip through, speeding up the whole way - fastest as it lands on
    the game's hit moment (0.2 s after the press, 0.3375 s for the
    finisher: Config.Weapons.Types.Sword),
  * and a long follow-through that carries on round the body past the
    enemy, slowing, the chest turned right round, the back foot pivoting.
The chest turns with the blade but a little AHEAD of it, and the arm leads
the blade into the hit and lets it fly past after (the wrist's whip) - the
body starts it, the blade finishes it. The cutting edge always faces the
way the blade travels.
"""
import math
import numpy as np

from anims import DirAnim, mix_dir, ease, slerp, unit

# THE STANCE: side-on, left foot forward, the blade low and pointing at the
# enemy's chest, the free hand relaxed - ready, not stiff
IDLE = {
    'root': (6, 0, -18),
    'legs': ((-0.28, -1, -0.34), (0.30, -1, 0.34)),
    'arm': ((0.25, -0.90, -0.35), (0.05, -0.18, -1.0), (0.0, 1.0, 0.0)),
    'larm': (-0.35, -0.92, -0.15),
    'look': (0, -0.08, -1),
    'hop': 0.0,
}
IDLE_IN = dict(IDLE, root=(7.5, 0, -17), arm=((0.25, -0.88, -0.38), (0.05, -0.15, -1.0), (0.0, 1.0, 0.0)),
               larm=(-0.36, -0.9, -0.12))


class PlaneSwing:
    """A swing round a plane: u = where the blade points at the hit, w = the
    way it's travelling then. keys: [(time, phi, easing into it, the rest)]
    where the rest is lean, tilt (the body), delta (how far the arm is ahead
    of the blade round the plane), legs, larm, look, hop - all keyed on the
    same moments. Before the first key it swings in from `start`; after the
    last it settles back into the stance by `settle`."""

    def __init__(self, name, u, w, keys, start, turn, settle, lead=0.025, arm_to=(0.1, -0.45, -1.0),
                 arm_mix=0.35, trail=None, priority='Action'):
        self.name, self.keys, self.start, self.settle = name, keys, start, settle
        self.u = unit(u)
        w = np.asarray(w, dtype=float)
        self.w = unit(w - (w @ self.u) * self.u)
        self.turn, self.lead = turn, lead
        self.arm_to, self.arm_mix = unit(arm_to), arm_mix
        self.length, self.loop, self.priority = settle, False, priority
        self.trail = trail  # (from, to): when the blade leaves a trail (the cut)

    def _key(self, t):
        ks = self.keys
        if t <= ks[0][0]:
            return ks[0][1], dict(ks[0][3])
        for (t0, p0, _, x0), (t1, p1, e, x1) in zip(ks, ks[1:]):
            if t <= t1:
                k = ease(e, (t - t0) / (t1 - t0))
                return p0 + (p1 - p0) * k, mix_dir(x0, x1, k)
        return ks[-1][1], dict(ks[-1][3])

    def _dir(self, phi_deg):
        p = math.radians(phi_deg)
        return math.cos(p) * self.u + math.sin(p) * self.w

    def on_plane(self, t):
        phi, x = self._key(t)
        b = self._dir(phi)
        e = self._dir(phi + 90)  # (the way it's moving: the edge faces that way)
        d = slerp(self._dir(phi + x.get('delta', 0)), self.arm_to, self.arm_mix)
        lead_phi, _ = self._key(t + self.lead)
        turn = self.turn[0] + self.turn[1] * lead_phi
        pose = {k: v for k, v in x.items() if k not in ('lean', 'tilt', 'delta', 'spin')}
        pose['root'] = (x.get('lean', 0), x.get('tilt', 0), turn)
        if x.get('spin'):  # (a spin: the legs go round with the body, by this much of the turn)
            pose['legspin'] = turn * x['spin']
        pose['arm'] = (d, b, e)
        return pose

    def at(self, t):
        first, last = self.keys[0][0], self.keys[-1][0]
        if t < first:
            return mix_dir(self.start, self.on_plane(first), ease('out', t / first))
        if t <= last:
            return self.on_plane(t)
        end = self.on_plane(last)
        # (after a spin: count the turn from where it came round to, so it settles
        # forward into the stance instead of unwinding back the way it came)
        lean, tilt, turn = end['root']
        while turn > 180:
            turn -= 360
            if 'legspin' in end:
                end['legspin'] -= 360
        end['root'] = (lean, tilt, turn)
        return mix_dir(end, dict(IDLE, legspin=0.0), ease('inout', (t - last) / (self.settle - last)))


def keys(*rows):
    """(time, phi, easing, lean, delta, legs, larm, look, hop[, tilt[, spin]])"""
    out = []
    for r in rows:
        t, phi, e, lean, delta, legs, larm, look, hop = r[:9]
        out.append((t, phi, e, {'lean': lean, 'tilt': r[9] if len(r) > 9 else 0, 'delta': delta,
                                'legs': legs, 'larm': larm, 'look': look, 'hop': hop,
                                'spin': r[10] if len(r) > 10 else 0}))
    return out


BACK = ((-0.30, -1, -0.40), (0.30, -1, 0.22))  # weight on the back foot
LUNGE = ((-0.22, -1, -0.62), (0.32, -1, 0.55))  # stepped in on the front foot
PIVOT = ((-0.24, -1, -0.62), (0.06, -1, 0.52))  # ...the back foot swung round behind
AHEAD = (0, -0.08, -1)  # eyes on the enemy
DOWN = (0, -0.22, -1)

# SWING 1: a flat forehand - coiled right back behind the right shoulder,
# whipped round level through the enemy at chest height, wrapping on round
# behind the left side
SWING1 = PlaneSwing(
    'SwordSwing1', u=(-0.25, 0.02, -1.0), w=(-1.0, -0.05, 0.25), start=IDLE, settle=0.85,
    turn=(6, 0.52), trail=(0.13, 0.40), arm_to=(0.1, -0.25, -1.0),
    keys=keys(
        (0.09, -150, 'out', 0, 30, BACK, (-0.12, -0.15, -1.0), AHEAD, 0.0),
        (0.13, -157, 'inout', -1, 38, BACK, (-0.10, -0.12, -1.0), AHEAD, 0.0),
        (0.20, 0, 'in2', 10, 0, LUNGE, (-0.55, -0.55, 0.60), AHEAD, 0.0),
        (0.36, 145, 'out2', 12, -25, PIVOT, (-0.12, -0.70, 0.70), AHEAD, 0.0),
        (0.50, 150, 'linear', 10, -20, PIVOT, (-0.25, -0.85, 0.45), AHEAD, 0.0),
    ))

# SWING 2: a rising backhand - from behind the left hip up through the enemy,
# finishing high over the right shoulder like a tennis backhand
SWING2 = PlaneSwing(
    'SwordSwing2', u=(0.35, 0.12, -1.0), w=(1.0, 0.70, 0.10), start=SWING1.at(0.5), settle=0.85,
    turn=(-8, -0.5), trail=(0.13, 0.40),
    keys=keys(
        (0.08, -140, 'out', 15, 30, PIVOT, (-0.20, -0.25, -1.0), AHEAD, 0.0),
        (0.13, -146, 'inout', 15, 38, PIVOT, (-0.20, -0.20, -1.0), AHEAD, 0.0),
        (0.20, 0, 'in2', 6, 0, LUNGE, (-0.50, -0.50, 0.60), AHEAD, 0.0),
        (0.36, 145, 'out2', -4, -25, ((-0.30, -1, -0.55), (0.34, -1, 0.40)), (-0.90, -0.30, 0.10), AHEAD, 0.0),
        (0.50, 150, 'linear', -2, -20, ((-0.30, -1, -0.55), (0.34, -1, 0.40)), (-0.80, -0.50, 0.10), AHEAD, 0.0),
    ))

# SWING 3, THE FINISHER: a leaping spin - coiled, then up off the ground and
# right round, body and legs and all, the blade flat and whipping through the
# enemy, landing wide
TUCK = ((-0.15, -1, -0.20), (0.15, -1, 0.10))
WIDE = ((-0.30, -1, -0.50), (0.32, -1, 0.42))
SWING3 = PlaneSwing(
    'SwordSwing3', u=(-0.20, 0.0, -1.0), w=(-1.0, 0.0, 0.20), start=SWING2.at(0.5), settle=1.2,
    turn=(8, 1.0), arm_to=(0.1, -0.2, -1.0), arm_mix=0.3, trail=(0.24, 0.62),
    keys=keys(
        (0.16, -110, 'out', 4, 25, BACK, (-0.10, -0.10, -1.0), AHEAD, 0.0, 0, 0.0),
        (0.24, -118, 'inout', 2, 32, BACK, (-0.10, -0.10, -1.0), AHEAD, 0.3, 0, 0.3),
        (0.3375, 0, 'in2', 8, 0, TUCK, (-0.90, -0.20, 0.30), AHEAD, 1.2, 0, 1.0),
        (0.60, 300, 'out2', 10, -20, WIDE, (-0.80, -0.30, 0.40), AHEAD, 0.0, 0, 1.0),
        (0.75, 305, 'linear', 8, -15, WIDE, (-0.60, -0.60, 0.40), AHEAD, 0.0, 0, 1.0),
    ))

ANIMS = {
    'SwordIdle': DirAnim('SwordIdle', [(0, IDLE, 'linear'), (1.2, IDLE_IN, 'inout'), (2.4, IDLE, 'inout')], loop=True, priority='Idle'),
    'SwordSwing1': SWING1,
    'SwordSwing2': SWING2,
    'SwordSwing3': SWING3,
}


class Timeline:
    """swings one after another, each pressed as its lock ends - how the whole
    string plays when you click through it - then the stance"""

    def __init__(self, parts, lead_in=0.25, tail=0.3):
        self.parts = []  # (start time, swing)
        t = lead_in
        for swing, gap in parts:
            self.parts.append((t, swing))
            t += gap
        last_t, last = self.parts[-1]
        self.lead_in = lead_in
        self.length = last_t + last.settle + tail
        self.loop = False

    def at(self, t):
        if t < self.lead_in:
            return dict(IDLE)
        for i, (t0, swing) in enumerate(self.parts):
            nxt = self.parts[i + 1][0] if i + 1 < len(self.parts) else math.inf
            if t < nxt:
                return swing.at(min(t - t0, swing.settle))
        return dict(IDLE)

    def trails(self):
        return [(t0 + s.trail[0], t0 + s.trail[1]) for t0, s in self.parts if s.trail]


COMBO = Timeline([(SWING1, 0.5), (SWING2, 0.5), (SWING3, 0)])

KEY_POSES = [('STANCE', IDLE)] + [
    ('%d %s' % (n + 1, label), s.at(t))
    for n, s in enumerate((SWING1, SWING2, SWING3))
    for label, t in (('COILED', s.keys[1][0]), ('HIT', s.keys[2][0]), ('FOLLOW-THROUGH', s.keys[3][0]))
]
