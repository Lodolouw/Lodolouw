"""The sword's animations, posed by direction (see anims.py: POSING BY
DIRECTION). Space: the character's own - x right, y up, -z forward (the
enemy). Every swing lands on the game's hit moment: 0.2 s after the press
for swings 1 and 2, 0.3375 s for the finisher (Config.Weapons.Types.Sword).
"""
from anims import DirAnim

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

# SWING 1: a diagonal slash, from over the right shoulder down to the low left
W1 = {  # wound up: chest turned away, the blade cocked back over the shoulder, weight back
    'root': (-3, 0, -42),
    'legs': ((-0.30, -1, -0.45), (0.30, -1, 0.25)),
    'arm': ((0.55, 0.62, 0.55), (0.15, 0.55, 0.82), (-0.5, 0.0, -0.85)),
    'larm': (-0.15, -0.25, -1.0),
    'look': (0, -0.05, -1),
    'hop': 0.0,
}
H1 = dict(W1, root=(-4, 0, -46), arm=((0.55, 0.66, 0.60), (0.15, 0.55, 0.82), (-0.5, 0.0, -0.85)))
C1 = {  # the hit: lunging in, the blade sweeping across in front, fastest here
    'root': (12, 0, 12),
    'legs': ((-0.25, -1, -0.62), (0.30, -1, 0.55)),
    'arm': ((0.05, -0.05, -1.0), (-0.62, -0.30, -0.72), (-0.6, -0.75, 0.2)),
    'larm': (-0.45, -0.70, 0.55),
    'look': (0, -0.15, -1),
    'hop': 0.0,
}
F1 = {  # ripped through: the chest turned left, the blade trailing low behind on the left
    'root': (16, 0, 42),
    'legs': ((-0.25, -1, -0.62), (0.30, -1, 0.55)),
    'arm': ((-0.72, -0.62, -0.30), (-0.35, -0.65, 0.68), (-0.2, -0.6, 0.75)),
    'larm': (-0.30, -0.80, 0.50),
    'look': (0.1, -0.2, -1),
    'hop': 0.0,
}
E1 = dict(F1, root=(14, 0, 38), arm=((-0.65, -0.62, -0.35), (-0.35, -0.60, 0.70), (-0.2, -0.6, 0.75)))

# SWING 2: a rising backhand, from the low left up to the high right
W2 = dict(F1, root=(14, 0, 50), arm=((-0.75, -0.55, 0.30), (-0.40, -0.45, 0.80), (0.5, 0.5, -0.7)))
C2 = {
    'root': (6, 0, -12),
    'legs': ((-0.25, -1, -0.55), (0.30, -1, 0.50)),
    'arm': ((-0.05, 0.05, -1.0), (0.60, 0.35, -0.72), (0.55, 0.8, 0.2)),
    'larm': (-0.40, -0.75, 0.45),
    'look': (0, -0.1, -1),
    'hop': 0.0,
}
F2 = {
    'root': (-2, 0, -44),
    'legs': ((-0.25, -1, -0.55), (0.30, -1, 0.50)),
    'arm': ((0.65, 0.62, -0.35), (0.30, 0.75, 0.60), (0.2, 0.6, 0.8)),
    'larm': (-0.25, -0.60, -0.75),
    'look': (-0.1, -0.05, -1),
    'hop': 0.0,
}
E2 = dict(F2, root=(0, 0, -40), arm=((0.60, 0.55, -0.40), (0.30, 0.70, 0.62), (0.2, 0.6, 0.8)))

# SWING 3, THE FINISHER: a leap with the blade high overhead, everything
# coming down with it into a deep lunge
W3 = {
    'root': (-6, 0, -8),
    'legs': ((-0.15, -1, -0.30), (0.18, -1, 0.05)),
    'arm': ((0.18, 0.95, 0.22), (0.05, 0.25, 0.97), (0, 1, -0.2)),
    'larm': (-0.30, 0.55, -0.80),
    'look': (0, 0.1, -1),
    'hop': 0.9,
}
H3 = dict(W3, root=(-8, 0, -6), arm=((0.15, 0.98, 0.25), (0.05, 0.22, 0.97), (0, 1, -0.2)), hop=1.1)
C3 = {
    'root': (26, 0, 2),
    'legs': ((-0.20, -1, -0.55), (0.25, -1, 0.48)),
    'arm': ((0.08, -0.55, -0.85), (0.0, -0.72, -0.70), (0, -1, 0.2)),
    'larm': (-0.40, -0.50, 0.75),
    'look': (0, -0.35, -1),
    'hop': 0.0,
}
F3 = dict(C3, root=(29, 0, 2), arm=((0.08, -0.70, -0.70), (0.0, -0.85, -0.50), (0, -1, 0.2)))
E3 = dict(F3, root=(24, 0, 0))

ANIMS = {
    'SwordIdle': DirAnim('SwordIdle', [(0, IDLE, 'linear'), (1.2, IDLE_IN, 'inout'), (2.4, IDLE, 'inout')], loop=True, priority='Idle'),
    'SwordSwing1': DirAnim('SwordSwing1', [(0, IDLE, 'linear'), (0.08, W1, 'out'), (0.13, H1, 'inout'), (0.20, C1, 'in'),
                                           (0.30, F1, 'out'), (0.50, E1, 'linear'), (0.85, IDLE, 'inout')]),
    'SwordSwing2': DirAnim('SwordSwing2', [(0, F1, 'linear'), (0.08, W2, 'out'), (0.20, C2, 'in'), (0.30, F2, 'out'),
                                           (0.50, E2, 'linear'), (0.85, IDLE, 'inout')]),
    'SwordSwing3': DirAnim('SwordSwing3', [(0, F2, 'linear'), (0.16, W3, 'out'), (0.26, H3, 'inout'), (0.3375, C3, 'in'),
                                           (0.44, F3, 'out'), (0.75, E3, 'linear'), (1.2, IDLE, 'inout')]),
}

# the whole string, pressed as fast as the game lets you (each swing starts
# once the last one's cut is through), then back to the stance
COMBO = DirAnim('Combo', [
    (0, IDLE, 'linear'), (0.25, IDLE, 'linear'),
    (0.33, W1, 'out'), (0.38, H1, 'inout'), (0.45, C1, 'in'), (0.55, F1, 'out'), (0.67, E1, 'linear'),
    (0.75, W2, 'out'), (0.87, C2, 'in'), (0.97, F2, 'out'), (1.09, E2, 'linear'),
    (1.25, W3, 'out'), (1.35, H3, 'inout'), (1.4275, C3, 'in'), (1.53, F3, 'out'), (1.84, E3, 'linear'),
    (2.3, IDLE, 'inout'), (2.6, IDLE, 'linear'),
])

KEY_POSES = [('STANCE', IDLE), ('1 WIND-UP', W1), ('1 HIT', C1), ('1 THROUGH', F1),
             ('2 WIND-UP', W2), ('2 HIT', C2), ('2 THROUGH', F2), ('3 LEAP', H3), ('3 HIT', C3), ('3 LANDED', F3)]
