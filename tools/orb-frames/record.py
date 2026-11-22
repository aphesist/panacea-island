"""Record orb2 frames as vector data for the island (QML). Usage: record.py OUTDIR [shape ...]"""
import json, sys, math
from pathlib import Path
from playwright.sync_api import sync_playwright
from shapely.geometry import Polygon
from shapely.validation import make_valid

HERE = Path(__file__).resolve().parent
SHAPES = ['circle', 'squircle', 'soft', 'wide', 'tall', 'bean', 'drop', 'ghost', 'triangle', 'hexagon',
          'diamond', 'cloud', 'clover', 'flower', 'star']
REACTIONS = ['idle', 'listening', 'thinking', 'working', 'compute', 'speaking', 'needs', 'done', 'error', 'sleeping']
FPS = 30
BODY_N = 80

LAST = [None]
def take(page, n, dt):
    """advance n frames of dt, return the drawn frame for each step (orb2 skips unchanged frames: repeat the last)"""
    out = []
    for _ in range(n):
        page.evaluate("window.__frames.length = 0")
        page.evaluate(f"__step({dt})")
        fr = page.evaluate("window.__frames.length ? window.__frames[window.__frames.length-1] : null")
        if fr is not None: LAST[0] = fr
        out.append(LAST[0])
    return out

def resample(pts, n):
    L = [0.0]
    for i in range(1, len(pts) + 1):
        a, b = pts[i - 1], pts[i % len(pts)]
        L.append(L[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    tot = L[-1] or 1; out = []; j = 0
    for k in range(n):
        d = tot * k / n
        while L[j + 1] < d: j += 1
        a, b = pts[j], pts[(j + 1) % len(pts)]
        seg = L[j + 1] - L[j]; t = (d - L[j]) / seg if seg > 1e-9 else 0
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    # start at the top-most point near the centre line, so any two bodies morph point to point
    i0 = min(range(n), key=lambda i: (abs(math.atan2(out[i][0], -out[i][1]))))
    return out[i0:] + out[:i0]

def fmt(v): return round(v, 3)

def ring_d(coords):
    c = list(coords)[:-1]
    return 'M' + 'L'.join(f'{fmt(x)} {fmt(y)}' for x, y in c) + 'Z'

def pack(fr):
    body = fr[0]
    bp = body['p'][0]
    poly = make_valid(Polygon(bp))
    b = resample(bp, BODY_N)
    eyes = {}
    for cell in fr[1:]:
        if cell['a'] < 0.01: continue
        for sp in cell['p']:
            if len(sp) < 3: continue
            g = make_valid(Polygon(sp)).intersection(poly)
            if g.is_empty: continue
            geoms = getattr(g, 'geoms', [g])
            d = ''.join(ring_d(x.exterior.coords) for x in geoms if x.geom_type == 'Polygon' and x.area > 1e-5)
            if d:
                a = round(cell['a'], 2)
                eyes[a] = eyes.get(a, '') + d
    return {'b': [fmt(v) for p in b for v in p], 'e': [[a, d] for a, d in sorted(eyes.items(), reverse=True)]}

def loop_cut(frames, min_len):
    """cut where the clip returns closest to its first frame, so it loops"""
    f0 = frames[0]['b']
    best, bi = 1e9, len(frames)
    for i in range(min_len, len(frames)):
        fb = frames[i]['b']
        d = sum(abs(x - y) for x, y in zip(f0, fb)) + 0.02 * abs(len(frames[i]['e']) - len(frames[0]['e']))
        d += 0 if frames[i]['e'] and frames[0]['e'] and len(frames[i]['e'][0][1]) == len(frames[0]['e'][0][1]) else 0.5
        if d < best: best, bi = d, i
    return frames[:bi]

def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    shapes = sys.argv[2:] or SHAPES
    with sync_playwright() as p:
        br = p.chromium.launch(executable_path='/usr/bin/chromium')
        page = br.new_page(viewport={'width': 300, 'height': 300})
        page.goto((HERE / 'page.html').as_uri())
        page.wait_for_timeout(300)
        dt = 1 / FPS
        for shape in shapes:
            page.evaluate(f"o.setAttribute('reaction','idle'); o.setAttribute('shape','{shape}'); o._sig = null")
            take(page, 60, dt)                                  # settle the shape morph
            data = {'shape': shape, 'fps': FPS, 'clips': {}}
            # the 360 turn (orb2's turntable spin), at 60 fps
            page.evaluate("o._nextBlink = 1e12")
            take(page, 10, dt)
            page.evaluate("o.spin('turntable')")
            data['clips']['spin'] = {'fps': 60, 'f': [pack(f) for f in take(page, 48, 1 / 60)]}
            take(page, 30, dt)
            for r in REACTIONS:
                page.evaluate(f"o.setAttribute('reaction','{r}')")
                enter = take(page, 15, dt)
                take(page, 30, dt)
                if r == 'idle':
                    page.evaluate("o._nextBlink = performance.now()/1000 + 1.2")
                frames = [pack(f) for f in take(page, 300, dt)]
                page.evaluate("o._nextBlink = 1e12")
                data['clips'][r] = {'fps': FPS, 'loop': True, 'f': loop_cut(frames, 60)}
                data['clips'][r + '>in'] = {'fps': FPS, 'f': [pack(f) for f in enter]}
                page.evaluate("o.setAttribute('reaction','idle')")
                data['clips'][r + '>out'] = {'fps': FPS, 'f': [pack(f) for f in take(page, 15, dt)]}
                take(page, 20, dt)
            (out / f'{shape}.json').write_text(json.dumps(data, separators=(',', ':')))
            n = sum(len(c['f']) for c in data['clips'].values())
            print(shape, n, 'frames', round((out / f'{shape}.json').stat().st_size / 1e6, 2), 'MB', flush=True)
        br.close()

if __name__ == '__main__':
    main()
