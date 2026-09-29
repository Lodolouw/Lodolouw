# Solves R6 arm angles (and the weapon's grip) from where the hands should be
# and which way the weapon should point, in the torso's own space (+x right,
# +y up, -z forward; shoulders at (+-1, 0.5, 0), head at y 1.5). Same maths as
# WeaponFX / render_sword.py (CFrame.Angles = Rx*Ry*Rz). Vectorised random
# search that narrows in, so a pose takes milliseconds.
import math, numpy as np

def cf(c):
    x,y,z,a,b,cc,d,e,f,g,h,i = c
    M=np.eye(4); M[:3,:3]=[[a,b,cc],[d,e,f],[g,h,i]]; M[:3,3]=[x,y,z]; return M
C = {'R': (cf([1,0.5,0,0,0,1,0,1,0,-1,0,0]), cf([-0.5,0.5,0,0,0,1,0,1,0,-1,0,0])),
     'L': (cf([-1,0.5,0,0,0,-1,0,1,0,1,0,0]), cf([0.5,0.5,0,0,0,-1,0,1,0,1,0,0]))}
PRE = {}
for side,(C0,C1) in C.items():
    C1i = np.linalg.inv(C1)
    v = C1i @ np.array([0,-1,0,1.0])
    PRE[side] = (C0[:3,:3], C0[:3,3], C1i[:3,:3], v[:3], C1i[:3,3])

def rotbatch(a):  # a: N x 3 degrees -> N x 3 x 3 (Rx*Ry*Rz)
    x, y, z = np.radians(a[:,0]), np.radians(a[:,1]), np.radians(a[:,2])
    cx, sx, cy, sy, cz, sz = np.cos(x), np.sin(x), np.cos(y), np.sin(y), np.cos(z), np.sin(z)
    N = len(a); R = np.empty((N,3,3))
    # Rx @ Ry @ Rz
    R[:,0,0] = cy*cz;              R[:,0,1] = -cy*sz;             R[:,0,2] = sy
    R[:,1,0] = sx*sy*cz + cx*sz;   R[:,1,1] = -sx*sy*sz + cx*cz;  R[:,1,2] = -sx*cy
    R[:,2,0] = -cx*sy*cz + sx*sz;  R[:,2,1] = cx*sy*sz + sx*cz;   R[:,2,2] = cx*cy
    return R

def kin(side, a, t=None, r=None):
    """hand positions and (if t given) weapon dir / local up / local x, for N candidates"""
    R0, T0, R1i, v, _ = PRE[side]
    A = rotbatch(a)
    hand = np.einsum('ij,njk,k->ni', R0, A, v) + T0
    if t is None:
        return hand, None, None, None
    tt, rr = np.radians(t), np.radians(r)
    ct, st, cr, sr = np.cos(tt), np.sin(tt), np.cos(rr), np.sin(rr)
    d_loc = np.stack([np.zeros_like(tt), st, -ct], 1)
    u_loc = np.stack([-sr, ct*cr, st*cr], 1)
    x_loc = np.stack([cr, ct*sr, st*sr], 1)
    M = np.einsum('ij,njk,kl->nil', R0, A, R1i)
    return hand, np.einsum('nij,nj->ni', M, d_loc), np.einsum('nij,nj->ni', M, u_loc), np.einsum('nij,nj->ni', M, x_loc)

def unit(v):
    v = np.array(v, float); return v / np.linalg.norm(v)

LIMITS = {'R': [(-110,110),(-130,130),(-60,240),(-200,200),(-220,220)],
          'L': [(-110,110),(-130,130),(-240,60),(-200,200),(-220,220)]}

def slerp(a, b, u):
    a, b = unit(a), unit(b)
    d = float(np.clip(a @ b, -1, 1))
    w = math.acos(d)
    if w < 1e-4:
        return unit(a + (b - a) * u)
    return (math.sin((1 - u) * w) * a + math.sin(u * w) * b) / math.sin(w)

def arc(a, b, via=None):
    """the path of the weapon's direction from a to b (through `via`, if given)"""
    if via is None:
        return lambda u: slerp(a, b, u)
    return lambda u: slerp(a, via, 2 * u) if u <= 0.5 else slerp(via, b, 2 * u - 1)

def pack(pose, k):
    """a solved pose as a parameter vector of length k"""
    return np.array((list(pose['a']) + [pose['t'], pose['r']])[:k], float)

def solve(side, seed, target=None, dirT=None, upT=None, xT=None, fixedGrip=None, freeRoll=False,
          reg=0.05, prev=None, pathDir=None, pathUp=None, pathX=None, pathHand=None, seedRng=0, wide=False):
    """seed/prev: a previous pose's parameters [x, y, z, tilt, roll]. The answer stays
    close to `prev` and, blended linearly from it (the way WeaponFX moves between
    key poses), keeps the weapon on pathDir(u) (and its edge on pathUp(u), the hand
    on pathHand(u)) at u = 0.25, 0.5, 0.75."""
    needW = (dirT is not None or upT is not None or xT is not None or pathDir is not None or pathUp is not None or pathX is not None)
    useGrip = needW and fixedGrip is None
    k = 3 + (1 if useGrip else 0) + (1 if useGrip and freeRoll else 0)
    lim = np.array(LIMITS[side][:k], float)
    base = np.array((list(seed) + [0, 0, 0, 0, 0])[:k], float)
    p0 = np.array((list(prev) + [0, 0, 0, 0, 0])[:k], float) if prev is not None else None
    fixedRoll = (seed[4] if len(seed) > 4 else 0.0)
    rng = np.random.RandomState(seedRng)
    def grips(P):
        if fixedGrip is not None:
            return np.full(len(P), fixedGrip[0], float), np.full(len(P), fixedGrip[1], float)
        if useGrip:
            return P[:, 3], (P[:, 4] if freeRoll else np.full(len(P), fixedRoll))
        return None, None
    def cost(P):
        t, r = grips(P)
        hand, d, u, x = kin(side, P[:, :3], t if needW else None, r if needW else None)
        e = np.zeros(len(P))
        if target is not None:
            e += np.sum((hand - np.array(target)) ** 2, 1)
        if dirT is not None: e += 3.0 * (1 - d @ unit(dirT))
        if upT is not None: e += 1.2 * (1 - u @ unit(upT))
        if xT is not None: e += 1.2 * (1 - x @ unit(xT))
        e += reg * np.sum(((P - base) / 90) ** 2, 1)
        if p0 is not None and (pathDir or pathUp or pathX or pathHand):
            for uu in (0.25, 0.5, 0.75):
                Pu = p0 + uu * (P - p0)
                tu, ru = grips(Pu)
                hu, du, upu, xu = kin(side, Pu[:, :3], tu if needW else None, ru if needW else None)
                if pathDir is not None: e += 2.0 * (1 - du @ pathDir(uu))
                if pathUp is not None: e += 0.6 * (1 - upu @ pathUp(uu))
                if pathX is not None: e += 0.6 * (1 - xu @ pathX(uu))
                if pathHand is not None: e += 0.6 * np.sum((hu - pathHand(uu)) ** 2, 1)
        lo, hi = lim[:, 0], lim[:, 1]
        e += np.sum((np.maximum(lo - P, 0) / 30) ** 2 + (np.maximum(P - hi, 0) / 30) ** 2, 1)
        return e
    # look round the seed (and, if asked, everywhere), then narrow in round the best few
    P = [base[None]]
    P.append(base + rng.normal(0, 60, (30000, k)))
    if wide:
        P.append(rng.uniform(lim[:, 0], lim[:, 1], (30000, k)))
    P = np.vstack(P)
    e = cost(P)
    best = P[np.argsort(e)[:24]]
    for sigma in [30, 20, 12, 8, 5, 3, 2, 1.2, 0.7, 0.4]:
        Q = np.vstack([best, np.repeat(best, 400, 0) + rng.normal(0, sigma, (len(best) * 400, k))])
        eq = cost(Q)
        best = Q[np.argsort(eq)[:24]]
    p = best[0]
    err = float(cost(p[None])[0])
    t, r = grips(p[None])
    tt = float(t[0]) if t is not None else 0.0
    rr = float(r[0]) if r is not None else 0.0
    hand, d, up, _ = kin(side, p[None, :3], np.array([tt]), np.array([rr]))
    return {'a': [int(round(v)) for v in p[:3]], 't': int(round(tt)), 'r': int(round(rr)), 'err': err,
            'hand': hand[0].round(2).tolist(), 'dir': d[0].round(2).tolist(), 'up': up[0].round(2).tolist(),
            'k': k}

if __name__ == '__main__':
    # sanity: matches the loop-based maths from before
    s = solve('R', [0,0,60], target=(1.5,-0.3,-1.3))
    print(s)
