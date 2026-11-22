# Post-pass over recorded orb clips: orb2 draws a new pose only every other recorded frame,
# so fill each 2-frame hold by interpolating to the next keyframe (body points, eye numbers, alpha),
# and keep the 80 body points' start index continuous (cyclic shift nearest the previous frame).
import json, re, sys, glob
import numpy as np
NUM = re.compile(r'-?\d+(?:\.\d+)?(?:e-?\d+)?')
def eye_key(e): return [(NUM.sub('#', p)) for _, p in e]
def eye_nums(e): return [[float(x) for x in NUM.findall(p)] for _, p in e]
def eye_lerp(ea, eb, w):
    if len(ea) != len(eb) or eye_key(ea) != eye_key(eb): return ea if w < 0.5 else eb
    out = []
    for (aa, pa), (ab, pb), na, nb in zip(ea, eb, eye_nums(ea), eye_nums(eb)):
        it = iter([round(x + (y - x) * w, 4) for x, y in zip(na, nb)])
        out.append([round(aa + (ab - aa) * w, 4), NUM.sub(lambda m: format(next(it), 'g'), pa)])
    return out
def align(prev, b):
    P = np.array(prev).reshape(-1, 2); B = np.array(b).reshape(-1, 2)
    d0 = np.abs(B - P).sum()
    best = min(range(len(B)), key=lambda s: np.abs(np.roll(B, -s, 0) - P).sum())
    if best == 0 or d0 < 1.0 or np.abs(np.roll(B, -best, 0) - P).sum() > 0.5 * d0: return b   # only real index jumps
    return np.roll(B, -best, 0).reshape(-1).round(4).tolist()
def fix(clip):
    f = clip['f']
    for i in range(1, len(f)): f[i]['b'] = align(f[i - 1]['b'], f[i]['b'])
    same = lambda a, b: a['b'] == b['b'] and a['e'] == b['e']
    n, filled = len(f), 0
    i = 0
    while i < n - 1:
        j = i + 1
        while j < n and same(f[j], f[i]): j += 1
        if j - i == 2 and j < n:            # a 2-frame hold followed by a new pose: the throttle
            a, b = f[i], f[j]
            a0 = f[i - 1] if i > 0 and not same(f[i - 1], a) else a      # Catmull-Rom midpoint: no velocity kink
            b1 = f[j + 1] if j + 1 < n else b
            mid = [(-p + 9 * x + 9 * y - q) / 16 for p, x, y, q in zip(a0['b'], a['b'], b['b'], b1['b'])]
            f[i + 1] = {'b': [round(v, 4) for v in mid], 'e': eye_lerp(a['e'], b['e'], 0.5)}
            filled += 1
        i = j
    if clip.get('loop') and n > 16:            # spread the seam error over the tail so the loop closes
        B = [np.array(x['b']) for x in f]
        d = [np.abs(B[k] - B[k - 1]).sum() for k in range(1, n)]
        nxt = B[-1] + (B[-1] - B[-2])          # where the tail would go next
        err = B[0] - nxt
        if np.abs(err).sum() > 2 * max(np.median(d), 0.05):
            N = min(n // 3, 24)
            for k in range(N):
                x = (k + 1) / N; w = x * x * x * (x * (x * 6 - 15) + 10)
                f[n - N + k]['b'] = (B[n - N + k] + err * w).round(4).tolist()
            clip['seamfix'] = N
    return filled
for p in sys.argv[1:]:
    d = json.load(open(p)); tot = 0
    for k, c in d['clips'].items(): tot += fix(c)
    json.dump(d, open(p, 'w'), separators=(',', ':'))
    print(p, 'filled', tot)
