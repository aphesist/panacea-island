/*!
 * <orb-avatar> v2 — expressive geometric avatars with custom body silhouettes & heavy shape-shifting eyes.
 * Zero-dependency Web Component rendered on <canvas> with crisp SVG export.
 * Docs: https://github.com/aphesist/orb2 · Demo: https://aphesist.github.io/orb2/
 * MIT License © 2026 Enzo Vasconcelos
 */
(() => {
'use strict';
if (typeof window === 'undefined' || !window.customElements || customElements.get('orb-avatar')) return;

const TAU = Math.PI * 2;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, p) => a + (b - a) * p;
const f4 = n => n.toFixed(4);
const RMQ = matchMedia('(prefers-reduced-motion: reduce)');
const num = (v, d) => { const n = parseFloat(v); return Number.isFinite(n) ? n : d; };
const on = v => v !== null && v !== 'false' && v !== 'off';

/* Smooth C2 quintic & asymmetric cushion curves — no acceleration jerk at endpoints */
const smooth5 = x => { const t = clamp(x, 0, 1); return t * t * t * (t * (t * 6 - 15) + 10); };
const lush = x => {                 // brisk launch (~26%), long silky cushion (~74%)
  const t = clamp(x, 0, 1);
  return t < .28 ? 0.5 * Math.pow(t / .28, 2.2) * .38 : 1 - 0.81 * Math.pow((1 - t) / .72, 3.1);
};
const easeMorph = x => { const t = clamp(x, 0, 1); return .45 * smooth5(t) + .55 * (1 - Math.pow(1 - t, 3.4)); };
const backOut = (x, c = 1.45) => { const t = clamp(x, 0, 1) - 1; return 1 + (c + 1) * t * t * t + c * t * t; };
const env = (e, a, b, c, d) => e < a ? 0 : e < b ? smooth5((e - a) / (b - a)) : e < c ? 1 : e < d ? 1 - smooth5((e - c) / (d - c)) : 0;
const pulse = (e, at, dur) => { const q = (e - at) / dur; return q > 0 && q < 1 ? Math.sin(q * Math.PI) : 0; };

/* ==========================================================================
   1. POLYGON RESAMPLING & GEOMETRIC PRIMITIVES
   ========================================================================== */

function signedArea(P) {
  let A = 0;
  for (let i = 0, n = P.length; i < n; i++) {
    const a = P[i], b = P[(i + 1) % n];
    A += a[0] * b[1] - b[0] * a[1];
  }
  return A * 0.5;
}

function polyCentroid(P) {
  let A = 0, cx = 0, cy = 0, n = P.length;
  for (let i = 0; i < n; i++) {
    const a = P[i], b = P[(i + 1) % n], cross = a[0] * b[1] - b[0] * a[1];
    A += cross; cx += (a[0] + b[0]) * cross; cy += (a[1] + b[1]) * cross;
  }
  if (Math.abs(A) < 1e-7) {
    for (const p of P) { cx += p[0]; cy += p[1]; }
    return [cx / (n || 1), cy / (n || 1)];
  }
  return [cx / (3 * A), cy / (3 * A)];
}

/**
 * Resample any closed outline to `N` arc-length-uniform points with consistent winding
 * and starting anchor at top-center (12 o'clock) so symmetric shapes morph symmetrically.
 * `yUp = true` for face space (+b is up), `yUp = false` for canvas body space (+y is down).
 */
function resample(P, N, yUp = true) {
  if (!P || P.length < 3) return Array.from({ length: N }, () => [0, 0]);
  const area = signedArea(P);
  // Clockwise visually: in yUp (+y up) signedArea < 0; in yDown (+y down) signedArea > 0
  if (yUp ? area > 0 : area < 0) P = P.slice().reverse();
  const [cx, cy] = polyCentroid(P);
  const topY = yUp ? 1 : -1;

  // Insert exact intersection or closest vertex near 12 o'clock (dx = 0, dy in top direction)
  let bestIdx = 0, bestScore = 1e9;
  for (let i = 0; i < P.length; i++) {
    const dx = P[i][0] - cx, dy = (P[i][1] - cy) * topY;
    const ang = Math.abs(Math.atan2(dx, dy));
    if (ang < bestScore) { bestScore = ang; bestIdx = i; }
  }
  const Q = P.slice(bestIdx).concat(P.slice(0, bestIdx));
  const n = Q.length, L = [0];
  for (let i = 1; i <= n; i++) {
    const a = Q[i - 1], b = Q[i % n];
    L.push(L[i - 1] + Math.hypot(b[0] - a[0], b[1] - a[1]));
  }
  const tot = L[n] || 1, out = [];
  let j = 0;
  for (let k = 0; k < N; k++) {
    const d = tot * k / N;
    while (j < n - 1 && L[j + 1] < d) j++;
    const a = Q[j], b = Q[(j + 1) % n], seg = L[j + 1] - L[j];
    const t = seg > 1e-8 ? (d - L[j]) / seg : 0;
    out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
  }
  return out;
}

/* ---------- Heavy, bold face-space primitives (+a right, +b up, units = ball radii) ---------- */

function rotPt(x, y, cx, cy, ang) {
  if (!ang) return [x, y];
  const c = Math.cos(ang), s = Math.sin(ang), dx = x - cx, dy = y - cy;
  return [cx + dx * c - dy * s, cy + dx * s + dy * c];
}

/**
 * Rounded rectangle / true stadium capsule.
 * When `r >= min(w, h)/2`, produces an exact geometric pill with semicircular caps.
 */
function rrect(cx, cy, w, h, r = Math.min(w, h) / 2, ang = 0, capSegs = 14) {
  const hw = w / 2, hh = h / 2, cr = clamp(r, 0.002, Math.min(hw, hh));
  const ix = hw - cr, iy = hh - cr, pts = [];
  // Clockwise in y-up space: top-center -> top-right -> bottom-right -> bottom-left -> top-left
  const arc = (ox, oy, a0, a1, n) => {
    for (let i = 0; i <= n; i++) {
      const a = lerp(a0, a1, i / n);
      pts.push(rotPt(cx + ox + Math.cos(a) * cr, cy + oy + Math.sin(a) * cr, cx, cy, ang));
    }
  };
  const line = (x0, y0, x1, y1, n = 4) => {
    for (let i = 1; i < n; i++) {
      const t = i / n;
      pts.push(rotPt(cx + lerp(x0, x1, t), cy + lerp(y0, y1, t), cx, cy, ang));
    }
  };
  if (ix > 1e-4) line(0, hh, ix, hh, 3);
  arc(ix, iy, Math.PI / 2, 0, capSegs);
  if (iy > 1e-4) line(hw, iy, hw, -iy, 6);
  arc(ix, -iy, 0, -Math.PI / 2, capSegs);
  if (ix > 1e-4) line(ix, -hh, -ix, -hh, 6);
  arc(-ix, -iy, -Math.PI / 2, -Math.PI, capSegs);
  if (iy > 1e-4) line(-hw, -iy, -hw, iy, 6);
  arc(-ix, iy, Math.PI, Math.PI / 2, capSegs);
  if (ix > 1e-4) line(-ix, hh, 0, hh, 3);
  return pts;
}

const pill = (cx, cy, w, h, ang = 0) => rrect(cx, cy, w, h, Math.min(w, h) / 2, ang, 16);
const superE = (cx, cy, w, h, n = 2.8, N = 64, ang = 0) => {
  const p = [];
  for (let i = 0; i < N; i++) {
    const t = Math.PI / 2 - i / N * TAU, c = Math.cos(t), s = Math.sin(t);
    p.push(rotPt(cx + w / 2 * Math.sign(c) * Math.abs(c) ** (2 / n), cy + h / 2 * Math.sign(s) * Math.abs(s) ** (2 / n), cx, cy, ang));
  }
  return p;
};
const ell = (cx, cy, rx, ry = rx, N = 56) => superE(cx, cy, rx * 2, ry * 2, 2, N);
const qb = (a, b, c, N = 24) => {
  const p = [];
  for (let i = 0; i <= N; i++) {
    const t = i / N, u = 1 - t;
    p.push([u * u * a[0] + 2 * u * t * b[0] + t * t * c[0], u * u * a[1] + 2 * u * t * b[1] + t * t * c[1]]);
  }
  return p;
};
const polyline = (pts, N = 12) => {
  const p = [];
  for (let i = 0; i < pts.length - 1; i++) {
    const A = pts[i], B = pts[i + 1];
    for (let k = 0; k < N; k++) { const t = k / N; p.push([lerp(A[0], B[0], t), lerp(A[1], B[1], t)]); }
  }
  p.push(pts[pts.length - 1]);
  return p;
};

/** Heavy round-capped stroke outline in face space */
function stroke(pts, w) {
  const h = w / 2, n = pts.length, L = [], R = [];
  const tan = i => {
    const A = pts[Math.max(0, i - 1)], B = pts[Math.min(n - 1, i + 1)];
    const dx = B[0] - A[0], dy = B[1] - A[1], l = Math.hypot(dx, dy) || 1;
    return [dx / l, dy / l];
  };
  for (let i = 0; i < n; i++) {
    const [tx, ty] = tan(i);
    L.push([pts[i][0] - ty * h, pts[i][1] + tx * h]);
    R.push([pts[i][0] + ty * h, pts[i][1] - tx * h]);
  }
  const out = L.slice(), tE = tan(n - 1), tS = tan(0), PE = pts[n - 1], PS = pts[0];
  for (let k = 1; k < 14; k++) {
    const a = Math.PI * k / 14, c = Math.cos(a), s = Math.sin(a);
    out.push([PE[0] + (-tE[1] * c + tE[0] * s) * h, PE[1] + (tE[0] * c + tE[1] * s) * h]);
  }
  for (let i = n - 1; i >= 0; i--) out.push(R[i]);
  for (let k = 1; k < 14; k++) {
    const a = Math.PI * k / 14, c = Math.cos(a), s = Math.sin(a);
    out.push([PS[0] + (tS[1] * c - tS[0] * s) * h, PS[1] + (-tS[0] * c - tS[1] * s) * h]);
  }
  return out;
}

function heavyPlus(cx, cy, span = .30, thick = .135) {
  const h = span / 2, t = thick / 2, ir = .022, pts = [];
  const arc = (ox, oy, rad, a0, a1, n = 8) => {
    for (let i = 0; i <= n; i++) { const a = lerp(a0, a1, i / n); pts.push([cx + ox + Math.cos(a) * rad, cy + oy + Math.sin(a) * rad]); }
  };
  arc(0, h - t, t, Math.PI, 0, 10);                                  // top round cap
  arc(t + ir, t + ir, ir, Math.PI, Math.PI * 1.5, 4);                // inner TR fillet
  arc(h - t, 0, t, Math.PI * 0.5, -Math.PI * 0.5, 10);               // right round cap
  arc(t + ir, -t - ir, ir, Math.PI * 0.5, Math.PI, 4);               // inner BR fillet
  arc(0, -h + t, t, 0, -Math.PI, 10);                                // bottom round cap
  arc(-t - ir, -t - ir, ir, 0, Math.PI * 0.5, 4);                    // inner BL fillet
  arc(-h + t, 0, t, -Math.PI * 0.5, -Math.PI * 1.5, 10);             // left round cap (clockwise via -PI)
  arc(-t - ir, t + ir, ir, -Math.PI * 0.5, 0, 4);                    // inner TL fillet
  return pts;
}

/**
 * Plush, zero-pointy Bauhaus capsule heart: union of two perpendicular round-capped pills
 * rotated 45°, with a full circular bottom cap and smooth concave top fillet.
 */
function pillHeart(cx, cy, s = 1) {
  const R = .080 * s, L = .112 * s, ir = .022 * s, S2 = Math.SQRT1_2;
  const yOff = L * S2 * 0.48, pts = [];
  const pushUV = (u, v) => pts.push([cx + (u - v) * S2, cy + (u + v) * S2 - yOff]);
  const arcUV = (ou, ov, rad, a0, a1, n) => {
    for (let i = 0; i <= n; i++) {
      const a = lerp(a0, a1, i / n);
      pushUV(ou + Math.cos(a) * rad, ov + Math.sin(a) * rad);
    }
  };
  const lineUV = (u0, v0, u1, v1, n = 5) => {
    for (let i = 1; i < n; i++) { const t = i / n; pushUV(lerp(u0, u1, t), lerp(v0, v1, t)); }
  };
  arcUV(R + ir, R + ir, ir, Math.PI, Math.PI * 1.5, 6);     // smooth concave top cleft
  lineUV(R + ir, R, L, R, 3);
  arcUV(L, 0, R, Math.PI * 0.5, -Math.PI * 0.5, 14);        // right pill lobe
  lineUV(L, -R, 0, -R, 6);
  arcUV(0, 0, R, -Math.PI * 0.5, -Math.PI, 10);             // plush circular bottom cap (no point!)
  lineUV(-R, 0, -R, L, 6);
  arcUV(0, L, R, Math.PI, 0, 14);                           // left pill lobe
  lineUV(R, L, R, R + ir, 3);
  return pts;
}

/** Plush round-nosed chevron (`>` or `<`) built from two round-capped capsules with circular vertex */
function pillChevron(cx, cy, pointDir = 1, arm = .20, R = .058, halfAng = 0.66) {
  const ca = Math.cos(halfAng), sa = Math.sin(halfAng), xOff = pointDir * arm * ca * 0.42;
  const vx = cx + xOff, vy = cy, outA = Math.PI * 0.5 - halfAng, inA = Math.PI * 1.5 - halfAng, pts = [];
  const push = (dx, dy) => pts.push([vx + dx * pointDir, vy + dy]);
  const arc = (ox, oy, rad, a0, a1, n = 10) => {
    for (let i = 0; i <= n; i++) { const a = lerp(a0, a1, i / n); push(ox + Math.cos(a) * rad, oy + Math.sin(a) * rad); }
  };
  const line = (x0, y0, x1, y1, n = 4) => {
    for (let i = 1; i < n; i++) { const t = i / n; push(lerp(x0, x1, t), lerp(y0, y1, t)); }
  };
  const ir = .018, dIn = (R + ir) / sa;
  arc(0, 0, R, outA, -outA, 10);                                              // plush round nose cap
  line(R * Math.cos(-outA), R * Math.sin(-outA), -arm * ca + R * Math.cos(-outA), -arm * sa + R * Math.sin(-outA), 5);
  arc(-arm * ca, -arm * sa, R, -outA, -inA, 12);                              // lower arm round cap
  line(-arm * ca - R * sa, -arm * sa + R * ca, -dIn + ir * sa, -ir * ca, 4);
  arc(-dIn, 0, ir, -outA, outA, 6);                                           // smooth inner nook
  line(-dIn + ir * sa, ir * ca, -arm * ca - R * sa, arm * sa - R * ca, 4);
  arc(-arm * ca, arm * sa, R, inA, outA, 12);                                 // upper arm round cap
  line(-arm * ca + R * Math.cos(outA), arm * sa + R * Math.sin(outA), R * Math.cos(outA), R * Math.sin(outA), 5);
  return pts;
}

const heart = (cx, cy, s = .30) => pillHeart(cx, cy, s / .30);

/* ==========================================================================
   2. SVG PATH PARSER & BODY SHAPE SYSTEM (Presets + Custom SVG Compatibility)
   ========================================================================== */

const BODY_N = 160;
const MEDIAL_N = 64;
const CAM_D = 15.0;   // Clean 85mm portrait telephoto perspective: crisp 3D depth without fisheye skew
const RAY_DIRS = Array.from({ length: BODY_N }, (_, i) => {
  const a = -Math.PI / 2 + i / BODY_N * TAU;
  return [Math.cos(a), Math.sin(a)];
});

function svgArcToPts(x1, y1, rx, ry, phiDeg, fa, fs, x2, y2) {
  if (Math.hypot(x2 - x1, y2 - y1) < 1e-6) return [];
  rx = Math.abs(rx); ry = Math.abs(ry);
  if (rx < 1e-6 || ry < 1e-6) return [[x2, y2]];
  const phi = phiDeg * Math.PI / 180, cp = Math.cos(phi), sp = Math.sin(phi);
  const dx2 = (x1 - x2) / 2, dy2 = (y1 - y2) / 2;
  const x1p = cp * dx2 + sp * dy2, y1p = -sp * dx2 + cp * dy2;
  let rxSq = rx * rx, rySq = ry * ry;
  const x1pSq = x1p * x1p, y1pSq = y1p * y1p;
  const lam = x1pSq / rxSq + y1pSq / rySq;
  if (lam > 1) { const s = Math.sqrt(lam); rx *= s; ry *= s; rxSq = rx * rx; rySq = ry * ry; }
  const sign = (fa === fs) ? -1 : 1;
  const numr = Math.max(0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq);
  const den = rxSq * y1pSq + rySq * x1pSq || 1;
  const coef = sign * Math.sqrt(numr / den);
  const cxp = coef * (rx * y1p / ry), cyp = coef * (-ry * x1p / rx);
  const cx = cp * cxp - sp * cyp + (x1 + x2) / 2, cy = sp * cxp + cp * cyp + (y1 + y2) / 2;
  const vAng = (ux, uy, vx, vy) => {
    const dot = ux * vx + uy * vy, len = Math.hypot(ux, uy) * Math.hypot(vx, vy) || 1;
    return (ux * vy - uy * vx < 0 ? -1 : 1) * Math.acos(clamp(dot / len, -1, 1));
  };
  const th1 = vAng(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let dth = vAng((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
  if (!fs && dth > 0) dth -= TAU;
  if (fs && dth < 0) dth += TAU;
  const steps = Math.max(8, Math.ceil(Math.abs(dth) / (Math.PI / 18))), pts = [];
  for (let i = 1; i <= steps; i++) {
    const a = th1 + dth * i / steps, ex = rx * Math.cos(a), ey = ry * Math.sin(a);
    pts.push([cp * ex - sp * ey + cx, sp * ex + cp * ey + cy]);
  }
  return pts;
}

/** Parse any SVG `d` path string into dense contours; returns largest outer contour */
function parseSVGPath(d) {
  const tokens = d.match(/[a-zA-Z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g);
  if (!tokens) return null;
  const contours = [];
  let cur = [], x = 0, y = 0, sx = 0, sy = 0, cx2 = 0, cy2 = 0, qx2 = 0, qy2 = 0, cmd = '', prev = '', idx = 0;
  const next = () => parseFloat(tokens[idx++]);
  const nextFlag = () => {
    const tok = tokens[idx];
    if (tok === '0' || tok === '1') { idx++; return +tok; }
    // Compact arc flag syntax like `a10 10 0 015 5`
    if (/^[01]/.test(tok)) {
      const f = +tok[0];
      tokens[idx] = tok.slice(1);
      return f;
    }
    return next();
  };
  const isCmd = t => /^[a-zA-Z]$/.test(t);

  while (idx < tokens.length) {
    if (isCmd(tokens[idx])) cmd = tokens[idx++];
    else if (cmd === 'M') cmd = 'L';
    else if (cmd === 'm') cmd = 'l';
    else if (!cmd) break;

    const rel = cmd === cmd.toLowerCase(), C = cmd.toUpperCase();
    if (C === 'M') {
      if (cur.length > 2) contours.push(cur);
      const nx = next() + (rel ? x : 0), ny = next() + (rel ? y : 0);
      x = sx = nx; y = sy = ny; cur = [[x, y]];
    } else if (C === 'Z') {
      if (cur.length > 2) { contours.push(cur); cur = []; }
      x = sx; y = sy;
    } else if (C === 'L' || C === 'H' || C === 'V') {
      const nx = C === 'V' ? x : next() + (rel ? x : 0);
      const ny = C === 'H' ? y : next() + (rel ? y : 0);
      const dist = Math.hypot(nx - x, ny - y), n = Math.max(1, Math.ceil(dist / 4));
      for (let i = 1; i <= n; i++) cur.push([lerp(x, nx, i / n), lerp(y, ny, i / n)]);
      x = nx; y = ny;
    } else if (C === 'C' || C === 'S') {
      const x1 = C === 'S' ? ((prev === 'C' || prev === 'S') ? 2 * x - cx2 : x) : next() + (rel ? x : 0);
      const y1 = C === 'S' ? ((prev === 'C' || prev === 'S') ? 2 * y - cy2 : y) : next() + (rel ? y : 0);
      const x2 = next() + (rel ? x : 0), y2 = next() + (rel ? y : 0);
      const x3 = next() + (rel ? x : 0), y3 = next() + (rel ? y : 0);
      for (let i = 1; i <= 20; i++) {
        const t = i / 20, u = 1 - t;
        cur.push([
          u * u * u * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
          u * u * u * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3
        ]);
      }
      cx2 = x2; cy2 = y2; x = x3; y = y3;
    } else if (C === 'Q' || C === 'T') {
      const x1 = C === 'T' ? ((prev === 'Q' || prev === 'T') ? 2 * x - qx2 : x) : next() + (rel ? x : 0);
      const y1 = C === 'T' ? ((prev === 'Q' || prev === 'T') ? 2 * y - qy2 : y) : next() + (rel ? y : 0);
      const x2 = next() + (rel ? x : 0), y2 = next() + (rel ? y : 0);
      for (let i = 1; i <= 16; i++) {
        const t = i / 16, u = 1 - t;
        cur.push([u * u * x + 2 * u * t * x1 + t * t * x2, u * u * y + 2 * u * t * y1 + t * t * y2]);
      }
      qx2 = x1; qy2 = y1; x = x2; y = y2;
    } else if (C === 'A') {
      const rx = next(), ry = next(), rot = next(), fa = nextFlag(), fs = nextFlag();
      const nx = next() + (rel ? x : 0), ny = next() + (rel ? y : 0);
      for (const p of svgArcToPts(x, y, rx, ry, rot, fa, fs, nx, ny)) cur.push(p);
      x = nx; y = ny;
    } else {
      break;
    }
    prev = C;
  }
  if (cur.length > 2) contours.push(cur);
  if (!contours.length) return null;
  contours.sort((a, b) => Math.abs(signedArea(b)) - Math.abs(signedArea(a)));
  return contours[0];
}

/** Extract points from an `<svg>` element or markup string (supports path, circle, ellipse, rect, polygon) */
function extractFromSVGElement(svgEl) {
  const candidates = [];
  for (const el of svgEl.querySelectorAll('path,polygon,rect,circle,ellipse')) {
    const tag = el.tagName.toLowerCase();
    let pts = null;
    if (tag === 'path') {
      const d = el.getAttribute('d');
      if (d) pts = parseSVGPath(d);
    } else if (tag === 'polygon') {
      const raw = (el.getAttribute('points') || '').trim().split(/[\s,]+/).map(Number);
      if (raw.length >= 6) {
        const poly = [];
        for (let i = 0; i + 1 < raw.length; i += 2) poly.push([raw[i], raw[i + 1]]);
        pts = polyline([...poly, poly[0]], 16);
      }
    } else if (tag === 'rect') {
      const w = num(el.getAttribute('width'), 100), h = num(el.getAttribute('height'), 100);
      const x = num(el.getAttribute('x'), 0) + w / 2, y = num(el.getAttribute('y'), 0) + h / 2;
      const rx = num(el.getAttribute('rx') ?? el.getAttribute('ry'), 0);
      pts = rrect(x, y, w, h, rx, 0, 14);
    } else if (tag === 'circle' || tag === 'ellipse') {
      const cx = num(el.getAttribute('cx'), 0), cy = num(el.getAttribute('cy'), 0);
      const rx = num(el.getAttribute('rx') ?? el.getAttribute('r'), 50);
      const ry = num(el.getAttribute('ry') ?? el.getAttribute('r'), 50);
      pts = ell(cx, cy, rx, ry, 96);
    }
    if (pts && pts.length > 2) candidates.push(pts);
  }
  if (!candidates.length) return null;
  candidates.sort((a, b) => Math.abs(signedArea(b)) - Math.abs(signedArea(a)));
  return candidates[0];
}

/** Signed distance from `(px, py)` to polygon `P` (+ inside, - outside) */
function signedDistPoly(px, py, P) {
  let inside = false, minD2 = Infinity;
  for (let i = 0, n = P.length, j = n - 1; i < n; j = i++) {
    const ax = P[i][0], ay = P[i][1], bx = P[j][0], by = P[j][1];
    if (((ay > py) !== (by > py)) && (px < (bx - ax) * (py - ay) / (by - ay || 1e-9) + ax)) inside = !inside;
    const dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy || 1e-9;
    const t = clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0, 1);
    const ex = ax + t * dx - px, ey = ay + t * dy - py, d2 = ex * ex + ey * ey;
    if (d2 < minD2) minD2 = d2;
  }
  return (inside ? 1 : -1) * Math.sqrt(minD2);
}

/** Normalize raw contour into `[-1, 1]²` canvas body space (+y down) and compute 3D face placement metadata */
function compileBodyShape(rawPts, opts = {}) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const [x, y] of rawPts) {
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (y < minY) minY = y; if (y > maxY) maxY = y;
  }
  const bw = (maxX - minX) || 1, bh = (maxY - minY) || 1, scale = 2 / Math.max(bw, bh);
  const midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
  const norm = rawPts.map(([x, y]) => [(x - midX) * scale, (y - midY) * scale]);
  const pts = resample(norm, BODY_N, false);

  // Find visual face center: blend area centroid + pole of inaccessibility (largest inscribed circle)
  const [cx, cy] = polyCentroid(pts);
  let bestX = cx, bestY = cy, bestR = signedDistPoly(cx, cy, pts);
  for (let step of [0.28, 0.08, 0.025]) {
    let bx = bestX, by = bestY;
    for (let gx = -3; gx <= 3; gx++) {
      for (let gy = -3; gy <= 3; gy++) {
        const tx = bx + gx * step, ty = by + gy * step;
        if (Math.abs(tx) > .95 || Math.abs(ty) > .95) continue;
        const d = signedDistPoly(tx, ty, pts);
        if (d > bestR) { bestR = d; bestX = tx; bestY = ty; }
      }
    }
  }
  const ox = opts.faceCenter ? opts.faceCenter[0] : (Math.abs(cx * .4 + bestX * .6) < .03 ? 0 : cx * .4 + bestX * .6);
  const oy = opts.faceCenter ? opts.faceCenter[1] : (Math.abs(cy * .35 + bestY * .65) < .03 ? 0 : cy * .35 + bestY * .65);

  // Measure horizontal & vertical clearance + vertical width taper (`taperY` keeps eyes inside narrow crowns!)
  const rayDistAt = (px, py, dx, dy) => {
    if (signedDistPoly(px, py, pts) <= 0) return 0.1;
    let lo = 0, hi = 1.4;
    for (let k = 0; k < 14; k++) {
      const m = (lo + hi) / 2;
      if (signedDistPoly(px + dx * m, py + dy * m, pts) > 0) lo = m; else hi = m;
    }
    return lo;
  };
  const clrX = Math.min(rayDistAt(ox, oy, 1, 0), rayDistAt(ox, oy, -1, 0));
  const clrY = Math.min(rayDistAt(ox, oy, 0, 1), rayDistAt(ox, oy, -1 + 1, -1));
  const clrTop = Math.min(rayDistAt(ox, oy - 0.34, 1, 0), rayDistAt(ox, oy - 0.34, -1, 0));
  const clrBot = Math.min(rayDistAt(ox, oy + 0.34, 1, 0), rayDistAt(ox, oy + 0.34, -1, 0));
  const taperY = opts.isCircle ? 0 : clamp((clrBot - clrTop) / (0.72 * Math.max(0.35, clrX)), -0.95, 0.95);
  const rx = clamp(clrX * 1.06, 0.64, 0.98);
  const ry = clamp(clrY * 1.06, 0.64, 0.98);
  const inR = clamp(bestR, 0.42, 1.0);
  const fScale = opts.faceScale ?? clamp(Math.pow(inR, 0.65), 0.72, 1.04);

  let floorY = -Infinity;
  for (const p of pts) if (p[1] > floorY) floorY = p[1];

  // Build Exact 3D Rounded Extrusion / Cushion (`(P_in x [-slabH, +slabH]) (+) B_3(bevelR)` + optional spherical `coreR`):
  // - Geometric badges/polygons (`squircle, triangle, hexagon, diamond, ghost, star`, custom SVGs):
  //   uniform `bevelR` + `slabH` with `coreR = 0` produces 100% straight, bump-free 3D beveled sides & crisp side profile!
  // - Plush lobular shapes (`cloud, soft, clover, flower`): 3D puff rim + inner `coreR` dome rounds smoothly at 90°!
  // - `drop`: smooth proportional medial inset (`insetFrac`) keeps a C-infinity teardrop profile across all 360°!
  const bevelR = opts.isCircle ? 1.0 : (opts.bevel ?? 0.19);
  const slabH = opts.isCircle ? 0 : (opts.slab ?? 0.05);
  const coreR = opts.isCircle ? 1.0 : Math.min(opts.core ?? 0, Math.max(0, bestR - 0.03));
  const camber = opts.isCircle ? 1.0 : (opts.camber ?? 0.34);
  const insetFrac = opts.insetFrac ?? 0;
  const spine = new Array(MEDIAL_N);
  let maxSpineR = 0;

  if (opts.isCircle) {
    for (let m = 0; m < MEDIAL_N; m++) spine[m] = [0, 0, 1.0];
    maxSpineR = 1.0;
  } else {
    const nPts = pts.length;
    for (let m = 0; m < MEDIAL_N; m++) {
      const i = Math.floor(m * nPts / MEDIAL_N);
      const prev = pts[(i - 1 + nPts) % nPts], cur = pts[i], next = pts[(i + 1) % nPts];
      const tx = next[0] - prev[0], ty = next[1] - prev[1], tl = Math.hypot(tx, ty) || 1;
      let nx = -ty / tl, ny = tx / tl;
      if (signedDistPoly(cur[0] + nx * 0.015, cur[1] + ny * 0.015, pts) < 0) { nx = -nx; ny = -ny; }
      let lo = 0.025, hi = insetFrac > 0 ? bestR * 0.99 : Math.min(bevelR, bestR * 0.98);
      if (hi < lo) hi = lo;
      for (let k = 0; k < 12; k++) {
        const mid = (lo + hi) * 0.5;
        if (signedDistPoly(cur[0] + nx * mid, cur[1] + ny * mid, pts) >= mid - 0.002) lo = mid;
        else hi = mid;
      }
      const r = insetFrac > 0 ? clamp(lo * insetFrac, 0.03, bestR * 0.95) : lo;
      if (r > maxSpineR) maxSpineR = r;
      spine[m] = [cur[0] + nx * r, cur[1] + ny * r, r];
    }
  }
  const zHalf = opts.isCircle ? 1.0 : (opts.zHalf ?? Math.max(maxSpineR + slabH, coreR));

  return {
    pts, spine, slabH, coreR, camber, zHalf, taperY,
    ox, oy, poleX: bestX, poleY: bestY,
    rx, ry, fScale, floorY, isCircle: !!opts.isCircle,
    label: opts.label || 'Custom'
  };
}

/* ---------- True 3D solids (sphere graph) ----------
 * Some silhouettes are not coins but complete 3D objects: the triangle is a rounded cone,
 * the cloud a lumpy cluster of puffs. A solid is a set of 3D spheres `[x, y, z, r]`
 * (+y down, +z toward the viewer) plus optional `links` (pairs whose sphere-swept hull is solid).
 * - `convex: true`  → the body is the convex hull of all spheres (cones, domes, gems, boxes).
 * - `convex: false` → the body is the union of spheres and linked sphere-swept capsules (clouds, stars).
 * The front-view silhouette is derived from the solid itself, so 2D outline and 3D body always agree.
 */
const HF_N = 48, HF_E = 1.18;
const _SQX = [], _SQY = [], _SQA = [];

function projectSolid(S, M) {
  const sp = S.sph, n = sp.length;
  for (let k = 0; k < n; k++) {
    const [x, y, z, r] = sp[k];
    const X = M.m00 * x + M.m01 * y + M.m02 * z;
    const Y = M.m10 * x + M.m11 * y + M.m12 * z;
    const Z = M.m20 * x + M.m21 * y + M.m22 * z;
    const persp = CAM_D / Math.max(2.0, CAM_D - Z);
    _SQX[k] = X * persp; _SQY[k] = Y * persp; _SQA[k] = r * persp;
  }
  const [cx, cy, cz] = S.center;
  const Zc = M.m20 * cx + M.m21 * cy + M.m22 * cz, pc = CAM_D / Math.max(2.0, CAM_D - Zc);
  return [(M.m00 * cx + M.m01 * cy + M.m02 * cz) * pc, (M.m10 * cx + M.m11 * cy + M.m12 * cz) * pc];
}

/** Raw projected outline of a solid under `M` (no scale/offset/jelly), `BODY_N / stride` points */
function solidOutline(S, M, stride) {
  const out = [], n = S.sph.length;
  const [ox, oy] = projectSolid(S, M);
  if (S.convex) {
    // Exact convex hull of the projected discs via the support function
    for (let i = 0; i < BODY_N; i += stride) {
      const nx = RAY_DIRS[i][0], ny = RAY_DIRS[i][1];
      let best = -Infinity, bk = 0;
      for (let k = 0; k < n; k++) {
        const h = _SQX[k] * nx + _SQY[k] * ny + _SQA[k];
        if (h > best) { best = h; bk = k; }
      }
      out.push([_SQX[bk] + nx * _SQA[bk], _SQY[bk] + ny * _SQA[bk]]);
    }
    return out;
  }
  // Union of discs + capsule hulls, ray-cast from the projected center
  const segs = [];
  for (const [i, j] of S.links) {
    const x0 = _SQX[i] - ox, y0 = _SQY[i] - oy, x1 = _SQX[j] - ox, y1 = _SQY[j] - oy;
    const a0 = _SQA[i], a1 = _SQA[j], da = a0 - a1;
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    if (len <= Math.abs(da) + 1e-6) continue;
    const ux = dx / len, uy = dy / len, ct = da / len, st = Math.sqrt(Math.max(0, 1 - ct * ct));
    for (let sgn = -1; sgn <= 1; sgn += 2) {
      const nx = ux * ct + sgn * uy * st, ny = uy * ct - sgn * ux * st;
      const ax = x0 + nx * a0, ay = y0 + ny * a0, bx = x1 + nx * a1, by = y1 + ny * a1;
      segs.push(ax, ay, bx, by, ax * by - ay * bx);
    }
  }
  for (let i = 0; i < BODY_N; i += stride) {
    const ux = RAY_DIRS[i][0], uy = RAY_DIRS[i][1];
    let bestT = 0;
    for (let k = 0; k < n; k++) {
      const qx = _SQX[k] - ox, qy = _SQY[k] - oy, a = _SQA[k];
      const perp = qx * uy - qy * ux, disc = a * a - perp * perp;
      if (disc > 0) { const t = qx * ux + qy * uy + Math.sqrt(disc); if (t > bestT) bestT = t; }
    }
    for (let g = 0; g < segs.length; g += 5) {
      const cA = segs[g] * uy - segs[g + 1] * ux, cB = segs[g + 2] * uy - segs[g + 3] * ux;
      if ((cA >= 0) !== (cB >= 0)) { const t = segs[g + 4] / (cA - cB); if (t > bestT) bestT = t; }
    }
    out.push([ox + ux * bestT, oy + uy * bestT]);
  }
  return out;
}

/** Front-surface heightfield (depth + normal) so eyes sit on the real 3D surface */
function buildHeightfield(S, frontPts) {
  const G = HF_N, Z = new Float32Array(G * G), NX = new Float32Array(G * G), NY = new Float32Array(G * G), NZ = new Float32Array(G * G);
  const ok = new Uint8Array(G * G);
  const sph = [];
  for (const s of S.sph) sph.push(s);
  if (!S.convex) {
    for (const [i, j] of S.links) {
      const A = S.sph[i], B = S.sph[j], L = Math.hypot(B[0] - A[0], B[1] - A[1], B[2] - A[2]);
      const steps = Math.max(2, Math.ceil(L / 0.025));
      for (let k = 1; k < steps; k++) {
        const u = k / steps;
        sph.push([lerp(A[0], B[0], u), lerp(A[1], B[1], u), lerp(A[2], B[2], u), lerp(A[3], B[3], u)]);
      }
    }
  }
  let dirs = null, hs = null;
  if (S.convex) {
    dirs = []; hs = [];
    const ND = 900, ga = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < ND; i++) {
      const z = 0.02 + 0.98 * (i + 0.5) / ND, rr = Math.sqrt(1 - z * z), a = i * ga;
      const d = [Math.cos(a) * rr, Math.sin(a) * rr, z];
      let h = -Infinity;
      for (const s of S.sph) h = Math.max(h, s[0] * d[0] + s[1] * d[1] + s[2] * d[2] + s[3]);
      dirs.push(d); hs.push(h);
    }
  }
  for (let gy = 0; gy < G; gy++) for (let gx = 0; gx < G; gx++) {
    const x = -HF_E + 2 * HF_E * gx / (G - 1), y = -HF_E + 2 * HF_E * gy / (G - 1), id = gy * G + gx;
    if (signedDistPoly(x, y, frontPts) < -0.01) continue;
    if (S.convex) {
      let best = Infinity, bd = null;
      for (let i = 0; i < dirs.length; i++) {
        const d = dirs[i], z = (hs[i] - d[0] * x - d[1] * y) / d[2];
        if (z < best) { best = z; bd = d; }
      }
      Z[id] = best; NX[id] = bd[0]; NY[id] = bd[1]; NZ[id] = bd[2]; ok[id] = 1;
    } else {
      let best = -Infinity, bs = null;
      for (const s of sph) {
        const dx = x - s[0], dy = y - s[1], q = s[3] * s[3] - dx * dx - dy * dy;
        if (q > 0) { const z = s[2] + Math.sqrt(q); if (z > best) { best = z; bs = s; } }
      }
      if (!bs) continue;
      Z[id] = best; NX[id] = (x - bs[0]) / bs[3]; NY[id] = (y - bs[1]) / bs[3]; NZ[id] = (best - bs[2]) / bs[3]; ok[id] = 1;
    }
  }
  // Extend the field past the rim (nearest valid cell) so off-face eye points still resolve
  for (let pass = 0; pass < G; pass++) {
    let changed = false;
    const prev = ok.slice();
    for (let gy = 0; gy < G; gy++) for (let gx = 0; gx < G; gx++) {
      const id = gy * G + gx;
      if (prev[id]) continue;
      for (const [ax, ay] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const qx = gx + ax, qy = gy + ay;
        if (qx < 0 || qy < 0 || qx >= G || qy >= G) continue;
        const q = qy * G + qx;
        if (prev[q] === 1) { Z[id] = Z[q]; NX[id] = NX[q]; NY[id] = NY[q]; NZ[id] = NZ[q]; ok[id] = 2; changed = true; break; }
      }
    }
    for (let i = 0; i < G * G; i++) if (ok[i] === 2) ok[i] = 1;
    if (!changed) break;
  }
  return { Z, NX, NY, NZ };
}

const H4 = [0, 0, 0, 1];
function sampleHF(hf, x, y) {
  const G = HF_N, fx = clamp((x + HF_E) / (2 * HF_E) * (G - 1), 0, G - 1.0001), fy = clamp((y + HF_E) / (2 * HF_E) * (G - 1), 0, G - 1.0001);
  const ix = fx | 0, iy = fy | 0, tx = fx - ix, ty = fy - iy, i00 = iy * G + ix, i10 = i00 + 1, i01 = i00 + G, i11 = i01 + 1;
  const bl = A => (A[i00] * (1 - tx) + A[i10] * tx) * (1 - ty) + (A[i01] * (1 - tx) + A[i11] * tx) * ty;
  const nx = bl(hf.NX), ny = bl(hf.NY), nz = bl(hf.NZ), nl = Math.hypot(nx, ny, nz) || 1;
  H4[0] = bl(hf.Z); H4[1] = nx / nl; H4[2] = ny / nl; H4[3] = nz / nl;
  return H4;
}

const M_ID = { m00: 1, m01: 0, m02: 0, m10: 0, m11: 1, m12: 0, m20: 0, m21: 0, m22: 1 };
/** Compile a 3D solid into a regular body (2D outline from its own front view + solid metadata) */
function compileSolid(spec, opts = {}) {
  let S = { sph: spec.sph.map(s => s.slice()), links: spec.links || [], convex: !!spec.convex, center: spec.center || [0, 0, 0] };
  // Normalize so the front view fits [-1, 1]² exactly like 2D silhouettes
  for (let pass = 0; pass < 2; pass++) {
    const raw = solidOutline(S, M_ID, 1);
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const [x, y] of raw) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    const k = 2 / Math.max(x1 - x0, y1 - y0), mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    S.sph = S.sph.map(([x, y, z, r]) => [(x - mx) * k, (y - my) * k, z * k, r * k]);
    S.center = [(S.center[0] - mx) * k, (S.center[1] - my) * k, S.center[2] * k];
  }
  const front = solidOutline(S, M_ID, 1);
  const body = compileBodyShape(front, { camber: 0.8, bevel: 0.3, slab: 0.05, ...opts });
  let zMax = 0;
  for (const s of S.sph) zMax = Math.max(zMax, Math.abs(s[2]) + s[3]);
  S.hf = buildHeightfield(S, body.pts);
  body.solid = S;
  body.zHalf = zMax;
  return body;
}

/**
 * Inflate any 2D outline (custom SVG) into a 3D body: spheres on the outline's medial axis, each
 * as big as the inscribed circle there. Head-on it matches the outline; turned, every part keeps a
 * round volume as thick as it is wide (thin arms stay thin, the belly stays full).
 */
function inflateBody(rawPts, opts = {}) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const [x, y] of rawPts) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
  const k = 2 / Math.max(maxX - minX || 1, maxY - minY || 1), mx = (minX + maxX) / 2, my = (minY + maxY) / 2;
  const pts = resample(rawPts.map(([x, y]) => [(x - mx) * k, (y - my) * k]), BODY_N, false);
  const cand = [];
  // Rim spheres (one per outline sample) keep corners crisp; a grid fills the inside
  for (let i = 0, n = pts.length; i < n; i++) {
    const prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    const tx = next[0] - prev[0], ty = next[1] - prev[1], tl = Math.hypot(tx, ty) || 1;
    let nx = -ty / tl, ny = tx / tl;
    if (signedDistPoly(cur[0] + nx * 0.015, cur[1] + ny * 0.015, pts) < 0) { nx = -nx; ny = -ny; }
    let lo = 0.02, hi = 0.22;
    for (let it = 0; it < 12; it++) {
      const mid = (lo + hi) / 2;
      if (signedDistPoly(cur[0] + nx * mid, cur[1] + ny * mid, pts) >= mid - 0.002) lo = mid; else hi = mid;
    }
    cand.push([cur[0] + nx * lo, cur[1] + ny * lo, lo]);
  }
  for (let gx = -1; gx <= 1.0001; gx += 0.05) for (let gy = -1; gy <= 1.0001; gy += 0.05) {
    const d = signedDistPoly(gx, gy, pts);
    if (d > 0.04) cand.push([gx, gy, d]);
  }
  cand.sort((p, q) => q[2] - p[2]);
  let keep = [];
  for (let eps = 0.004; ; eps *= 2) {
    keep = [];
    for (const c of cand) if (!keep.some(q => Math.hypot(c[0] - q[0], c[1] - q[1]) + c[2] <= q[2] + eps)) keep.push(c);
    if (keep.length <= 200 || eps > 0.1) break;
  }
  const big = keep[0];
  return compileSolid({ convex: false, center: [big[0], big[1], 0], sph: keep.map(([x, y, r]) => [x, y, 0, r]) }, opts);
}

/** Ring of `n` spheres around the vertical axis (solid-of-revolution building block) */
const ring = (y, R, r, n = 18, phase = 0) =>
  Array.from({ length: n }, (_, i) => { const a = phase + i / n * TAU; return [Math.cos(a) * R, y, Math.sin(a) * R, r]; });

/* ---------- Built-in Body Silhouettes ---------- */
const SHAPES = {};
const customShapeCache = new Map();

function regShape(name, label, pts, opts = {}) {
  SHAPES[name] = compileBodyShape(pts, { label, ...opts });
}

// Polar generator in canvas space (+y down, starting from top -PI/2 clockwise)
function polarBody(fn, N = 192) {
  const p = [];
  for (let i = 0; i < N; i++) {
    const a = -Math.PI / 2 + i / N * TAU, r = fn(a);
    p.push([Math.cos(a) * r, Math.sin(a) * r]);
  }
  return p;
}
function superBody(w, h, n = 2, rot = 0, N = 192) {
  const p = [];
  for (let i = 0; i < N; i++) {
    const t = -Math.PI / 2 + i / N * TAU, c = Math.cos(t), s = Math.sin(t);
    const x = w * Math.sign(c) * Math.abs(c) ** (2 / n);
    const y = h * Math.sign(s) * Math.abs(s) ** (2 / n);
    p.push(rotPt(x, y, 0, 0, rot));
  }
  return p;
}
function roundedPolyBody(sides, radius = 1, cornerR = 0.28, rotOffset = -Math.PI / 2) {
  const verts = [];
  for (let i = 0; i < sides; i++) {
    const a = rotOffset + i / sides * TAU;
    verts.push([Math.cos(a) * radius, Math.sin(a) * radius]);
  }
  const pts = [], halfAng = Math.PI * (sides - 2) / (2 * sides), dTrim = cornerR / Math.tan(halfAng);
  for (let i = 0; i < sides; i++) {
    const prev = verts[(i - 1 + sides) % sides], cur = verts[i], next = verts[(i + 1) % sides];
    const ux = prev[0] - cur[0], uy = prev[1] - cur[1], ul = Math.hypot(ux, uy) || 1;
    const vx = next[0] - cur[0], vy = next[1] - cur[1], vl = Math.hypot(vx, vy) || 1;
    const p1 = [cur[0] + ux / ul * dTrim, cur[1] + uy / ul * dTrim];
    const p2 = [cur[0] + vx / vl * dTrim, cur[1] + vy / vl * dTrim];
    const bx = ux / ul + vx / vl, by = uy / ul + vy / vl, bl = Math.hypot(bx, by) || 1;
    const distC = cornerR / Math.sin(halfAng);
    const cx = cur[0] + bx / bl * distC, cy = cur[1] + by / bl * distC;
    const a1 = Math.atan2(p1[1] - cy, p1[0] - cx);
    let da = Math.atan2(p2[1] - cy, p2[0] - cx) - a1;
    while (da <= -Math.PI) da += TAU;
    while (da > Math.PI) da -= TAU;
    for (let k = 0; k <= 16; k++) {
      const a = a1 + da * k / 16;
      pts.push([cx + Math.cos(a) * cornerR, cy + Math.sin(a) * cornerR]);
    }
    const nextPrev = verts[i], nextCur = next;
    const nux = nextPrev[0] - nextCur[0], nuy = nextPrev[1] - nextCur[1], nul = Math.hypot(nux, nuy) || 1;
    const np1 = [nextCur[0] + nux / nul * dTrim, nextCur[1] + nuy / nul * dTrim];
    for (let k = 1; k < 8; k++) pts.push([lerp(p2[0], np1[0], k / 8), lerp(p2[1], np1[1], k / 8)]);
  }
  return pts;
}

regShape('circle', 'Circle', polarBody(() => 1), { faceCenter: [0, 0], faceScale: 1, isCircle: true });
// Every built-in silhouette is a complete 3D object, so it reads as itself from every side:
// solids of revolution (cone, drop, dome, mallow, pill) keep their outline through a spin, while
// boxes, prisms, gems and puff clusters show their real depth as they turn.
SHAPES.squircle = compileSolid({
  // Rounded box: eight corner spheres, a little shallower than wide
  convex: true, center: [0, 0, 0],
  sph: [-1, 1].flatMap(x => [-1, 1].flatMap(y => [-1, 1].map(z => [x * 0.62, y * 0.62, z * 0.40, 0.38])))
}, { label: 'Squircle', faceCenter: [0, 0], faceScale: 1 });
// Rounded cone: small apex puff over a soft circular base (a solid of revolution, not a flat plectrum)
SHAPES.triangle = compileSolid({
  convex: true, center: [0, 0.25, 0],
  sph: [[0, -0.66, 0, 0.30], ...ring(0.56, 0.60, 0.36, 20)]
}, { label: 'Triangle', faceCenter: [0, 0.14], faceScale: 0.88 });
// Cloud: a lumpy cluster of 3D puffs around a big core, so it stays a cloud from every side
SHAPES.cloud = compileSolid({
  convex: false, center: [0, 0.05, 0],
  sph: [
    [0, 0.04, 0, 0.70],
    [-0.56, 0.20, 0.02, 0.40], [0.58, 0.16, -0.02, 0.42],
    [-0.24, -0.38, 0.04, 0.44], [0.30, -0.34, -0.04, 0.40],
    [-0.20, 0.36, 0.10, 0.42], [0.24, 0.38, -0.08, 0.40]
  ]
}, { label: 'Cloud', faceCenter: [0, 0.04], faceScale: 0.94 });
SHAPES.soft = compileSolid({
  // Marshmallow: a soft cylinder of revolution, slightly wider at its base
  convex: true, center: [0, 0, 0],
  sph: [...ring(-0.52, 0.64, 0.38, 20), ...ring(0.52, 0.72, 0.38, 20)]
}, { label: 'Soft', faceCenter: [0, 0.03], faceScale: 0.98 });
SHAPES.tall = compileSolid({
  // Standing pill: a capsule of revolution
  convex: true, center: [0, 0, 0],
  sph: [[0, -0.34, 0, 0.72], [0, 0.34, 0, 0.72]]
}, { label: 'Tall', faceCenter: [0, -0.06], faceScale: 0.84 });
SHAPES.wide = compileSolid({
  // Lying pill: a horizontal capsule that turns end-on into a ball
  convex: true, center: [0, 0, 0],
  sph: [[-0.34, 0, 0, 0.72], [0.34, 0, 0, 0.72]]
}, { label: 'Wide', faceCenter: [0, 0], faceScale: 0.92 });
SHAPES.bean = compileSolid({
  // Leaning pebble: a capsule tipped slightly off vertical
  convex: true, center: [0, 0, 0],
  sph: [[-0.09, -0.33, 0, 0.70], [0.09, 0.33, 0, 0.70]]
}, { label: 'Bean', faceCenter: [0, -0.02], faceScale: 0.84 });
// Drop: a teardrop of revolution (round belly + small tip on one vertical axis). Its outline holds
// through a spin, only the eyes travel round; a hard tilt shows a little more of the belly.
SHAPES.drop = compileSolid({
  convex: true, center: [0, 0.2, 0],
  sph: [[0, 0.30, 0, 0.70], [0, -0.20, 0, 0.42], [0, -0.82, 0, 0.12]]
}, { label: 'Drop', faceCenter: [0, 0.15], faceScale: 0.88 });
SHAPES.ghost = compileSolid({
  // Dome: a round crown over a flat, softly rounded base (a bell of revolution)
  convex: true, center: [0, 0.1, 0],
  sph: [[0, -0.10, 0, 0.86], ...ring(0.64, 0.66, 0.24, 20)]
}, { label: 'Dome', faceCenter: [0, 0.04], faceScale: 0.94 });
SHAPES.clover = compileSolid({
  // Four puffs around a raised core
  convex: false, center: [0, 0, 0],
  sph: [[0, 0, 0.06, 0.50], ...[0, 1, 2, 3].map(k => { const a = k * Math.PI / 2; return [Math.cos(a) * 0.50, Math.sin(a) * 0.50, 0, 0.46]; })]
}, { label: 'Clover', faceCenter: [0, 0], faceScale: 0.92 });
SHAPES.flower = compileSolid({
  // Six petal puffs in a ring with a domed centre
  convex: false, center: [0, 0, 0],
  sph: [[0, 0, 0.10, 0.46], ...[0, 1, 2, 3, 4, 5].map(k => { const a = -Math.PI / 2 + k * Math.PI / 3; return [Math.cos(a) * 0.58, Math.sin(a) * 0.58, 0, 0.36]; })]
}, { label: 'Flower', faceCenter: [0, 0], faceScale: 0.88 });
SHAPES.diamond = compileSolid({
  // Gem: a rounded, slightly flattened octahedron; its side points sweep into depth as it turns
  convex: true, center: [0, 0, 0],
  sph: [[0, -0.84, 0, 0.16], [0, 0.84, 0, 0.16], [-0.80, 0, 0, 0.16], [0.80, 0, 0, 0.16], [0, 0, 0.16, 0.44], [0, 0, -0.16, 0.44]]
}, { label: 'Lozenge', faceCenter: [0, 0], faceScale: 0.88 });
SHAPES.hexagon = compileSolid({
  // Thick hex coin (prism): ~45% of its width edge-on, flat sides, rounded edges, as in the reference
  convex: true, center: [0, 0, 0],
  sph: [-1, 1].flatMap(z => [0, 1, 2, 3, 4, 5].map(k => { const a = -Math.PI / 2 + k * Math.PI / 3; return [Math.cos(a) * 0.76, Math.sin(a) * 0.76, z * 0.22, 0.24]; }))
}, { label: 'Hexagon', faceCenter: [0, 0], faceScale: 0.92 });
SHAPES.star = compileSolid({
  // Puffy star: five cone arms swept from a round core out to soft tips
  convex: false, center: [0, 0.04, 0],
  sph: [[0, 0.06, 0, 0.44], ...[0, 1, 2, 3, 4].map(k => { const a = -Math.PI / 2 + k * TAU / 5; return [Math.cos(a) * 0.80, Math.sin(a) * 0.80 + 0.06, 0, 0.17]; })],
  links: [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
}, { label: 'Spark', faceCenter: [0, 0.04], faceScale: 0.86 });

function resolveBodyShape(spec, slottedSVG) {
  if (slottedSVG) {
    const key = 'slot:' + slottedSVG.innerHTML;
    if (!customShapeCache.has(key)) {
      const raw = extractFromSVGElement(slottedSVG);
      if (raw) customShapeCache.set(key, inflateBody(raw));
    }
    if (customShapeCache.has(key)) return customShapeCache.get(key);
  }
  if (!spec || SHAPES[spec]) return SHAPES[spec] || SHAPES.circle;
  const trimmed = spec.trim();
  if (customShapeCache.has(trimmed)) return customShapeCache.get(trimmed);

  let raw = null;
  if (trimmed.startsWith('#') && typeof document !== 'undefined') {
    const el = document.querySelector(trimmed);
    if (el) raw = el.tagName.toLowerCase() === 'svg' ? extractFromSVGElement(el) : extractFromSVGElement({ querySelectorAll: () => [el] });
  } else if (trimmed.startsWith('<')) {
    const tpl = document.createElement('template');
    tpl.innerHTML = trimmed;
    const svg = tpl.content.querySelector('svg') || tpl.content;
    raw = extractFromSVGElement(svg);
  } else if (/^[mM]/.test(trimmed)) {
    raw = parseSVGPath(trimmed);
  }
  if (raw && raw.length > 2) {
    const compiled = inflateBody(raw);
    if (customShapeCache.size > 64) customShapeCache.clear();
    customShapeCache.set(trimmed, compiled);
    return compiled;
  }
  return SHAPES.circle;
}

function mixBody(A, B, p) {
  if (p <= 0) return A;
  if (p >= 1) return B;
  const pts = new Array(BODY_N);
  for (let i = 0; i < BODY_N; i++) {
    pts[i] = [lerp(A.pts[i][0], B.pts[i][0], p), lerp(A.pts[i][1], B.pts[i][1], p)];
  }
  const spine = new Array(MEDIAL_N);
  for (let i = 0; i < MEDIAL_N; i++) {
    const sa = A.spine[i], sb = B.spine[i];
    spine[i] = [lerp(sa[0], sb[0], p), lerp(sa[1], sb[1], p), lerp(sa[2], sb[2], p)];
  }
  return {
    pts,
    spine,
    slabH: lerp(A.slabH, B.slabH, p),
    coreR: lerp(A.coreR, B.coreR, p),
    camber: lerp(A.camber, B.camber, p),
    zHalf: lerp(A.zHalf, B.zHalf, p),
    taperY: lerp(A.taperY, B.taperY, p),
    ox: lerp(A.ox, B.ox, p),
    oy: lerp(A.oy, B.oy, p),
    poleX: lerp(A.poleX, B.poleX, p),
    poleY: lerp(A.poleY, B.poleY, p),
    rx: lerp(A.rx, B.rx, p),
    ry: lerp(A.ry, B.ry, p),
    fScale: lerp(A.fScale, B.fScale, p),
    floorY: lerp(A.floorY, B.floorY, p),
    isCircle: A.isCircle && B.isCircle,
    label: B.label,
    // Both ends are kept: the outline and eyes are projected for each and blended per frame,
    // so 3D solids and extruded coins morph into each other without a pop at either end.
    mix: [A, B, p]
  };
}

/** Radius of a closed outline along ray `(ux, uy)` from the origin (farthest crossing) */
function rayHit(P, ux, uy) {
  let best = 0;
  for (let i = 0, n = P.length, j = n - 1; i < n; j = i++) {
    const ax = P[j][0], ay = P[j][1], bx = P[i][0], by = P[i][1];
    const ex = bx - ax, ey = by - ay, den = ex * uy - ey * ux;
    if (Math.abs(den) < 1e-12) continue;
    const t = (ex * ay - ey * ax) / den, u = (ux * ay - uy * ax) / den;
    if (u >= -1e-7 && u <= 1 + 1e-7 && t > best) best = t;
  }
  return best;
}

/* ==========================================================================
   3. MULTI-CELL EYE PRIMITIVES & TOPOLOGICAL MORPHING ENGINE
   ==========================================================================
   Every eye (`L` or `R`) is a cluster of 1..9 solid, bold closed cells (`CELL_N = 64` pts).
   No thin lines, no hollow outlines — optical ink weight stays constant across states!
   ========================================================================== */

const CELL_N = 64;
const EX_X = 0.24;     // Horizontal eye center spacing (±0.24 in sphere radii)
const EX_Y = 0.05;     // Slightly above midline for friendly proportion
const SW = 0.145;      // Heavy stroke width for curved/chevron states (matches pill weight!)

function makeCell(pts, cx, cy, fill = 'eye', opts = {}) {
  return { pts: resample(pts, CELL_N, true), c: [cx, cy], fill, op: opts.op ?? 1, noBlink: !!opts.noBlink };
}

/* ---------- 16 Heavy Solid Eye Shape Builders (`eyeShape(side, opts)`) ---------- */
const EYE_SHAPES = {
  /** Iconic vertical capsule pill (default) */
  pill: (s, o = {}) => {
    const cx = (o.x ?? s * EX_X), cy = (o.y ?? EX_Y);
    return [makeCell(pill(cx, cy, o.w ?? .19, o.h ?? .42, o.ang ?? 0), cx, cy)];
  },
  /** Extra-tall expressive pill */
  tall: (s, o = {}) => {
    const cx = (o.x ?? s * EX_X), cy = (o.y ?? EX_Y);
    return [makeCell(pill(cx, cy, o.w ?? .18, o.h ?? .50, o.ang ?? 0), cx, cy)];
  },
  /** Chunky solid circle (matches optical ink area of vertical pill) */
  circle: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .005)), cy = (o.y ?? EX_Y), r = o.r ?? .152;
    return [makeCell(ell(cx, cy, r, r, 64), cx, cy)];
  },
  /** Bold horizontal / sideways pill */
  wide: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .018)), cy = (o.y ?? EX_Y);
    return [makeCell(pill(cx, cy, o.w ?? .35, o.h ?? .175, o.ang ?? 0), cx, cy)];
  },
  /** Half-height heavy squint capsule */
  squint: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .01)), cy = (o.y ?? EX_Y);
    return [makeCell(pill(cx, cy, o.w ?? .28, o.h ?? .185, o.ang ?? 0), cx, cy)];
  },
  /** Heavy rounded square block */
  square: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .008)), cy = (o.y ?? EX_Y), sz = o.sz ?? .275;
    return [makeCell(rrect(cx, cy, sz, sz, sz * .28, o.ang ?? 0, 12), cx, cy)];
  },
  /** 2x2 matrix of 4 bold rounded sub-blocks per eye */
  grid: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .018)), cy = (o.y ?? EX_Y);
    const off = o.off ?? .098, sz = o.sz ?? .144, scales = o.scales;
    const cells = [];
    let idx = 0;
    for (const dy of [off, -off]) {
      for (const dx of [-off, off]) {
        const k = scales ? scales[idx] : 1;
        const w = sz * k;
        cells.push(makeCell(rrect(cx + dx, cy + dy, w, w, w * .36, 0, 10), cx + dx, cy + dy));
        idx++;
      }
    }
    return cells;
  },
  /** 3x3 pixel dot-matrix per eye */
  matrix: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .024)), cy = (o.y ?? EX_Y);
    const off = o.off ?? .112, sz = o.sz ?? .088, scales = o.scales;
    const cells = [];
    let idx = 0;
    for (const dy of [off, 0, -off]) {
      for (const dx of [-off, 0, off]) {
        const k = scales ? scales[idx] : 1;
        const w = sz * k;
        cells.push(makeCell(rrect(cx + dx, cy + dy, w, w, w * .42, 0, 8), cx + dx, cy + dy));
        idx++;
      }
    }
    return cells;
  },
  /** Dual vertical capsule bars (`||` per eye — voice / equalizer) */
  bars: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .012)), cy = (o.y ?? EX_Y);
    const off = o.off ?? .084, w = o.w ?? .118, h1 = o.h1 ?? .36, h2 = o.h2 ?? .36;
    return [
      makeCell(pill(cx - off, cy, w, h1), cx - off, cy),
      makeCell(pill(cx + off, cy, w, h2), cx + off, cy)
    ];
  },
  /** Dual horizontal capsule stack (`=` per eye) */
  stack: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .015)), cy = (o.y ?? EX_Y);
    const off = o.off ?? .086, w = o.w ?? .31, h = o.h ?? .118;
    return [
      makeCell(pill(cx, cy + off, w, h), cx, cy + off),
      makeCell(pill(cx, cy - off, w, h), cx, cy - off)
    ];
  },
  /** Bold happy upward arc `^` */
  arc: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .01)), cy = (o.y ?? EX_Y);
    return [makeCell(stroke(qb([cx - .13, cy - .055], [cx, cy + .14], [cx + .13, cy - .055], 20), o.sw ?? SW), cx, cy, 'eye', { noBlink: true })];
  },
  /** Bold calm resting curve `︶` */
  rest: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .01)), cy = (o.y ?? (EX_Y - .03));
    return [makeCell(stroke(qb([cx - .13, cy + .04], [cx, cy - .11], [cx + .13, cy + .04], 20), o.sw ?? (SW * .95)), cx, cy, 'eye', { noBlink: true })];
  },
  /** Bold inward chevrons `> <` with plush round nose */
  chevron: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .016)), cy = (o.y ?? EX_Y), dir = -s * (o.dir ?? 1);
    return [makeCell(pillChevron(cx, cy, dir, o.arm ?? .20, o.r ?? .058), cx, cy, 'eye', { noBlink: true })];
  },
  /** Focused slanted heavy pill (`\ /` inward slant by default, `dir: -1` for sad `/ \`) */
  slant: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .012)), cy = (o.y ?? EX_Y);
    const ang = (o.ang ?? 0.42) * s * (o.dir ?? 1);
    return [makeCell(pill(cx, cy, o.w ?? .33, o.h ?? .17, ang), cx, cy)];
  },
  /** Bold geometric cross `+` */
  plus: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .016)), cy = (o.y ?? EX_Y), span = o.span ?? .34, thick = o.thick ?? .15;
    const poly = heavyPlus(cx, cy, span, thick);
    const pts = o.ang ? poly.map(([x, y]) => rotPt(x, y, cx, cy, o.ang)) : poly;
    return [makeCell(pts, cx, cy)];
  },
  /** Chunky rotated diamond */
  diamond: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .012)), cy = (o.y ?? EX_Y), sz = o.sz ?? .27;
    return [makeCell(rrect(cx, cy, sz, sz, sz * .26, Math.PI / 4 + (o.ang ?? 0), 12), cx, cy)];
  },
  /** Bold plush capsule heart (no pointy bottom!) */
  heart: (s, o = {}) => {
    const cx = (o.x ?? s * (EX_X + .018)), cy = (o.y ?? EX_Y);
    return [makeCell(pillHeart(cx, cy, (o.sz ?? .32) / .30), cx, cy)];
  }
};

const STATIC_EYE_CACHE = new Map();
function buildEye(name, side, opts) {
  const fn = EYE_SHAPES[name] || EYE_SHAPES.pill;
  if (!opts) {
    const key = name + ':' + side;
    let c = STATIC_EYE_CACHE.get(key);
    if (!c) { c = fn(side); STATIC_EYE_CACHE.set(key, c); }
    return c;
  }
  return fn(side, opts);
}

function pairEyes(leftSpec, rightSpec) {
  if (rightSpec === undefined) {
    if (typeof leftSpec === 'string' && /\s/.test(leftSpec.trim())) {
      const parts = leftSpec.trim().split(/\s+/);
      leftSpec = parts[0]; rightSpec = parts[1] || parts[0];
    } else {
      rightSpec = leftSpec;
    }
  }
  const resolveSide = (spec, s) => {
    if (typeof spec === 'string') return buildEye(spec, s);
    if (Array.isArray(spec)) return buildEye(spec[0], s, spec[1]);
    return spec;
  };
  return { L: resolveSide(leftSpec, -1), R: resolveSide(rightSpec, 1), extras: [] };
}

function mixCell(a, b, p) {
  if (p <= 0) return a;
  if (p >= 1) return b;
  const pts = new Array(CELL_N);
  for (let i = 0; i < CELL_N; i++) {
    pts[i] = [lerp(a.pts[i][0], b.pts[i][0], p), lerp(a.pts[i][1], b.pts[i][1], p)];
  }
  return {
    pts,
    c: [lerp(a.c[0], b.c[0], p), lerp(a.c[1], b.c[1], p)],
    fill: p < .5 ? a.fill : b.fill,
    op: lerp(a.op ?? 1, b.op ?? 1, p),
    noBlink: p < .5 ? a.noBlink : b.noBlink
  };
}

/**
 * Multi-cell Fission / Fusion morph between cell cluster `A` (M cells) and `B` (K cells).
 * Because cells are opaque solid shapes, overlapping cells at p=0 or p=1 have zero seam,
 * and splitting/merging cells peel apart or coalesce with smooth per-cell micro-stagger!
 */
function mixCluster(A, B, p) {
  if (p <= 0.0005) return A;
  if (p >= 0.9995) return B;
  const m = A.length, k = B.length;
  if (m === k) {
    const out = new Array(m);
    const stg = m > 1 ? 0.12 / (m - 1) : 0;
    for (let i = 0; i < m; i++) {
      const pi = m > 1 ? easeMorph(clamp((p - i * stg) / (1 - 0.12), 0, 1)) : p;
      out[i] = mixCell(A[i], B[i], pi);
    }
    return out;
  }
  if (m === 1) {
    // Fission: 1 solid shape splits cleanly into K cells
    const out = new Array(k), span = Math.min(0.18, 0.045 * (k - 1));
    const stg = k > 1 ? span / (k - 1) : 0;
    for (let j = 0; j < k; j++) {
      const pj = easeMorph(clamp((p - j * stg) / (1 - span), 0, 1));
      out[j] = mixCell(A[0], B[j], pj);
    }
    return out;
  }
  if (k === 1) {
    // Fusion: M cells coalesce cleanly into 1 solid shape
    const out = new Array(m), span = Math.min(0.18, 0.045 * (m - 1));
    const stg = m > 1 ? span / (m - 1) : 0;
    for (let i = 0; i < m; i++) {
      const pi = easeMorph(clamp((p - i * stg) / (1 - span), 0, 1));
      out[i] = mixCell(A[i], B[0], pi);
    }
    return out;
  }
  // General M <-> K correspondence by spatial proximity
  const pairs = [];
  if (m < k) {
    for (let j = 0; j < k; j++) {
      let best = 0, bestD = 1e9;
      for (let i = 0; i < m; i++) {
        const d = Math.hypot(A[i].c[0] - B[j].c[0], A[i].c[1] - B[j].c[1]);
        if (d < bestD) { bestD = d; best = i; }
      }
      pairs.push([A[best], B[j]]);
    }
  } else {
    for (let i = 0; i < m; i++) {
      let best = 0, bestD = 1e9;
      for (let j = 0; j < k; j++) {
        const d = Math.hypot(A[i].c[0] - B[j].c[0], A[i].c[1] - B[j].c[1]);
        if (d < bestD) { bestD = d; best = j; }
      }
      pairs.push([A[i], B[best]]);
    }
  }
  return pairs.map(([ca, cb], idx) => {
    const span = 0.14, stg = pairs.length > 1 ? span / (pairs.length - 1) : 0;
    return mixCell(ca, cb, easeMorph(clamp((p - idx * stg) / (1 - span), 0, 1)));
  });
}

/** Mix complete face `{ L, R, extras }` with subtle L->R lead-follow stagger */
function mixFaces(FA, FB, rawP, stagger = 0.055) {
  if (rawP <= 0.0005) return FA;
  if (rawP >= 0.9995) return FB;
  const pL = easeMorph(clamp(rawP / (1 - stagger), 0, 1));
  const pR = easeMorph(clamp((rawP - stagger) / (1 - stagger), 0, 1));
  const pE = easeMorph(rawP);

  // Extra features (e.g. optional blush)
  const exMap = new Map();
  for (const f of (FA.extras || [])) exMap.set(f.key, [f, null]);
  for (const f of (FB.extras || [])) {
    const cur = exMap.get(f.key);
    if (cur) cur[1] = f; else exMap.set(f.key, [null, f]);
  }
  const extras = [];
  for (const [key, [a, b]] of exMap) {
    if (a && b) extras.push({ ...mixCell(a, b, pE), key });
    else {
      const f = a || b, s = a ? Math.max(0, 1 - pE * 1.4) : backOut(Math.min(1, pE * 1.15));
      const op = (f.op ?? 1) * (a ? Math.max(0, 1 - pE * 1.6) : Math.min(1, pE * 1.8));
      extras.push({ ...f, key, op, pts: f.pts.map(q => [f.c[0] + (q[0] - f.c[0]) * s, f.c[1] + (q[1] - f.c[1]) * s]) });
    }
  }
  return { L: mixCluster(FA.L, FB.L, pL), R: mixCluster(FA.R, FB.R, pR), extras };
}

/** Step through timed face keyframes with silky overlapping morphs: `seqFace(e, [[0, F0], [0.9, F1], ...], morphDur)` */
function seqFace(e, steps, blend = 0.28) {
  let i = 0;
  while (i + 1 < steps.length && e >= steps[i + 1][0]) i++;
  const cur = typeof steps[i][1] === 'function' ? steps[i][1](e) : steps[i][1];
  if (i === 0) return cur;
  const dt = e - steps[i][0], dur = steps[i][2] ?? blend;
  if (dt >= dur) return cur;
  const prev = typeof steps[i - 1][1] === 'function' ? steps[i - 1][1](e) : steps[i - 1][1];
  return mixFaces(prev, cur, dt / dur, 0.05);
}

/** Step through timed eye-gaze targets `[time, eyeYaw, eyePitch, eyeRoll]` with smooth quintic glide */
function seqGaze(e, stops, glide = 0.24) {
  let i = 0;
  while (i + 1 < stops.length && e >= stops[i + 1][0]) i++;
  const cur = stops[i];
  if (i === 0) return { eyaw: cur[1], epitch: cur[2], eroll: cur[3] || 0 };
  const prev = stops[i - 1], dur = cur[4] ?? glide, p = lush(clamp((e - cur[0]) / dur, 0, 1));
  return {
    eyaw: lerp(prev[1], cur[1], p),
    epitch: lerp(prev[2], cur[2], p),
    eroll: lerp(prev[3] || 0, cur[3] || 0, p)
  };
}

/* ==========================================================================
   4. REACTIONS & PURE EYE-CHOREOGRAPHY EMOTES
   ========================================================================== */

const hop = (t, period, dur, amp) => { const p = (t % period) / dur; return p > 1 ? {} : { dy: -amp * Math.sin(p * Math.PI) }; };

const F_PILL = pairEyes('pill');
const F_CIRCLE = pairEyes('circle');
const F_WIDE = pairEyes('wide');
const F_SQUARE = pairEyes('square');
const F_GRID = pairEyes('grid');
const F_MATRIX = pairEyes('matrix');
const F_BARS = pairEyes('bars');
const F_STACK = pairEyes('stack');
const F_ARC = pairEyes('arc');
const F_REST = pairEyes('rest');
const F_CHEVRON = pairEyes('chevron');
const F_PLUS = pairEyes('plus');
const F_DIAMOND = pairEyes('diamond');
const F_SQUINT = pairEyes('squint');
const F_TALL = pairEyes('tall');
const F_HEART = pairEyes('heart');

const EX = {
  idle: {
    label: 'Idle', blink: true, useEyeShape: true,
    face: (t, e, eyeShape) => pairEyes(eyeShape || 'pill'),
    motion: null
  },
  listening: {
    label: 'Listening', blink: true,
    face: t => {
      // Expressive inquisitive circles with subtle Grok-style asymmetric size modulation
      const asym = Math.sin(t * 1.45) * .022;
      return pairEyes(['circle', { r: .158 + asym }], ['circle', { r: .158 - asym }]);
    },
    motion: t => {
      const cyc = (t * .38) % 1;
      const yaw = cyc < .45 ? .34 : cyc < .78 ? -.26 : .08;
      const pitch = cyc < .45 ? .18 : cyc < .78 ? -.12 : .24;
      const roll = cyc < .45 ? .16 : cyc < .78 ? -.14 : .06;
      return { eyaw: yaw, epitch: pitch, bodyRoll: roll, w: .78, s: 1 + .014 * Math.sin(t * 2.4) };
    }
  },
  thinking: {
    label: 'Thinking', blink: true, extra: 'dots',
    face: t => {
      // Smoothly alternates between tall pills looking skyward and asymmetric narrow focus
      const p = .5 + .5 * Math.sin(t * 1.3);
      return p > .62
        ? pairEyes(['pill', { h: .38, y: EX_Y + .02 }], ['wide', { w: .31, h: .175, y: EX_Y + .01 }])
        : F_PILL;
    },
    motion: t => {
      const side = Math.sin(t * .65) > 0 ? 1 : -1;
      return { eyaw: side * .48, epitch: .66 + .10 * Math.sin(t * 1.5), w: .92, bodyRoll: side * .14 + .03 * Math.sin(t * 1.2) };
    }
  },
  compute: {
    label: 'Compute', extra: 'dots',
    face: t => {
      // 2x2 grid per eye with smooth traveling wave modulation across cells
      const sc = off => [0, 1, 2, 3].map(i => .82 + .26 * Math.sin(t * 5.2 - i * 1.1 - off));
      return pairEyes(['grid', { scales: sc(0) }], ['grid', { scales: sc(1.4) }]);
    },
    motion: t => ({ eyaw: .36 * Math.sin(t * 1.05), epitch: .18 * Math.cos(t * 1.5), bodyRoll: .08 * Math.sin(t * 1.05), w: .85 })
  },
  working: {
    label: 'Working', blink: true,
    face: t => {
      const up = Math.sin(t * .7) > .25;
      return up ? F_WIDE : pairEyes(['slant', { w: .33, h: .175, ang: .22 }], ['slant', { w: .33, h: .175, ang: .22 }]);
    },
    motion: t => {
      const cyc = (t * .48) % 1;
      const x = cyc < .78 ? lerp(-.58, .58, smooth5(cyc / .78)) : lerp(.58, -.58, smooth5((cyc - .78) / .22));
      const y = Math.sin(t * .7) > .25 ? .52 : -.18;
      return { eyaw: x, epitch: y, bodyRoll: x * .16, w: .92 };
    }
  },
  speaking: {
    label: 'Speaking',
    face: t => {
      // Lively conversational cadence: voice-modulated capsules & inquisitive circles
      const phrase = (t * .42) % 1;
      if (phrase > .68) {
        const pulseR = .148 + .024 * Math.sin(t * 10.5);
        return pairEyes(['circle', { r: pulseR + .014 }], ['circle', { r: pulseR - .01 }]);
      }
      const a = .22 + .22 * (.5 + .5 * Math.sin(t * 9.5));
      const b = .22 + .22 * (.5 + .5 * Math.sin(t * 9.5 + 1.3));
      const c = .22 + .22 * (.5 + .5 * Math.sin(t * 9.5 + 2.5));
      const d = .22 + .22 * (.5 + .5 * Math.sin(t * 9.5 + 0.6));
      return pairEyes(['bars', { h1: a, h2: b }], ['bars', { h1: c, h2: d }]);
    },
    motion: t => ({
      eyaw: .38 * Math.sin(t * 1.15) + .16 * Math.cos(t * 2.3),
      epitch: .22 * Math.sin(t * 1.5 + .8) + .08,
      bodyRoll: .13 * Math.sin(t * 1.15),
      w: .82,
      s: 1 + .016 * Math.sin(t * 9.5)
    })
  },
  happy: {
    label: 'Happy',
    face: () => F_ARC,
    motion: t => ({ dy: -.08 * Math.abs(Math.sin(t * 1.55 * Math.PI)), epitch: .12, w: .35 })
  },
  done: {
    label: 'Done', extra: 'sparkle',
    face: () => F_ARC,
    motion: t => ({ ...hop(t, 2.4, .46, .11), epitch: .28, w: .45 })
  },
  needs: {
    label: 'Needs you', blink: true, extra: 'ring',
    face: () => F_TALL,
    motion: t => ({ ...hop(t, 2.0, .42, .07), eyaw: 0, epitch: .08, w: .7 })
  },
  sleeping: {
    label: 'Sleeping', extra: 'zzz',
    face: () => F_REST,
    motion: t => ({ eyaw: .08, epitch: -.34, bodyRoll: .10, w: .92, s: 1 + .014 * Math.sin(t * 1.5) })
  },
  error: {
    label: 'Error',
    face: () => F_CHEVRON,
    motion: t => {
      const b = Math.max(0, Math.sin(t * 2.2)) ** 10;
      return { epitch: .02, w: .55, yawAdd: .12 * Math.sin(t * 42) * b, bodyRoll: .05 * Math.sin(t * 42) * b };
    }
  },
  wink: {
    label: 'Wink',
    face: () => pairEyes('pill', 'arc'),
    motion: () => ({ bodyRoll: .09, eyaw: .16, epitch: .14, w: .5 })
  },
  skeptic: {
    label: 'Skeptic', blink: true,
    face: () => pairEyes('pill', 'wide'),
    motion: () => ({ bodyRoll: -.06, eyaw: -.18, epitch: .08, w: .6 })
  },
  love: {
    label: 'Love', extra: 'heart',
    face: () => F_HEART,
    motion: t => ({ epitch: .20, w: .4, bodyRoll: .08 * Math.sin(t * 2.1), s: 1 + .02 * Math.sin(t * 5.2) })
  },
  sad: {
    label: 'Sad', blink: true,
    face: () => pairEyes(['slant', { dir: -1, ang: .30, y: EX_Y - .03 }], ['slant', { dir: -1, ang: .30, y: EX_Y - .03 }]),
    motion: () => ({ epitch: -.30, eyaw: -.12, bodyRoll: -.05, w: .75 })
  },
  dizzy: {
    label: 'Dizzy', extra: 'orbit',
    face: t => pairEyes(['plus', { ang: t * 3.4 }], ['plus', { ang: -t * 3.4 }]),
    motion: t => ({ bodyRoll: .10 * Math.sin(t * 2.4), eyaw: .14 * Math.cos(t * 2.4), epitch: .08 * Math.sin(t * 2.4), w: .75 })
  },
  // Hidden poke reactions (clean, heavy geometric states)
  surprised: {
    label: 'Surprised', hidden: true,
    face: () => pairEyes(['circle', { r: .17 }], ['circle', { r: .17 }]),
    motion: (t, e) => ({ dy: e < .34 ? -.09 * Math.sin(e / .34 * Math.PI) : 0, eyaw: 0, epitch: .12, w: .8 })
  },
  giggle: {
    label: 'Giggle', hidden: true,
    face: () => F_ARC,
    motion: (t, e) => ({ dy: -.045 * Math.abs(Math.sin(e * 11)) * Math.exp(-e * 2.2), bodyRoll: .09 * Math.sin(e * 15) * Math.exp(-e * 2.4), eyaw: 0, epitch: .16, w: .6 })
  }
};

/* ---------- Pure Eye-Movement & Shape-Shifting Choreographies (Emotes) ---------- */
const defEmote = (label, dur, weight, def) => ({ label, hidden: true, emote: { dur, weight, kicks: def.kicks || [] }, ...def });

Object.assign(EX, {
  /** Signature cycle: Pill -> Circle -> 2x2 Grid -> Sideways Pill -> Pill */
  shapeshift: defEmote('Shape shift', 4.4, 5, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.35, F_CIRCLE, .34],
      [1.30, F_GRID, .38],
      [2.45, F_WIDE, .38],
      [3.55, pairEyes(eyeShape || 'pill'), .38]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .05], [.4, .22, .14], [1.35, -.24, .06], [2.5, .20, -.06], [3.55, 0, .05]], .32),
      w: .92
    })
  }),

  /** Pill -> Square -> Rippling 2x2 Grid -> Circle -> Pill */
  pixelate: defEmote('Pixelate', 4.2, 4, {
    face: (t, e, eyeShape) => {
      const waveGrid = u => {
        const sc = off => [0, 1, 2, 3].map(i => .78 + .30 * Math.sin(u * 8 - i * 1.2 - off));
        return pairEyes(['grid', { scales: sc(0) }], ['grid', { scales: sc(1.2) }]);
      };
      return seqFace(e, [
        [0, F_PILL],
        [0.30, F_SQUARE, .30],
        [1.05, waveGrid, .34],
        [2.65, F_CIRCLE, .34],
        [3.45, pairEyes(eyeShape || 'pill'), .36]
      ]);
    },
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .04], [.35, -.16, .12], [1.1, .18, .08], [2.7, 0, .14], [3.5, 0, .04]], .28),
      w: .88
    })
  }),

  /** Crisp eye-only saccade scan in sideways-pill focus mode */
  scan: defEmote('Scan lines', 3.4, 4, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.22, F_WIDE, .26],
      [2.75, pairEyes(eyeShape || 'pill'), .32]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [
        [0, 0, .04],
        [0.25, -.46, .16, 0, .20],
        [0.85, .46, .16, 0, .42],
        [1.45, -.46, -.10, 0, .18],
        [2.05, .46, -.10, 0, .42],
        [2.75, 0, .04, 0, .26]
      ]),
      w: .96
    })
  }),

  /** Staggered L/R mechanical-yet-silky calibration: Pill -> Wide -> Plus -> Circle -> Pill */
  calibrate: defEmote('Calibrate', 4.0, 3, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.30, pairEyes('wide', 'pill'), .26],
      [0.65, F_WIDE, .26],
      [1.35, F_PLUS, .32],
      [2.25, F_DIAMOND, .30],
      [2.90, F_CIRCLE, .30],
      [3.45, pairEyes(eyeShape || 'pill'), .34]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .05], [.35, -.18, .06], [.7, .18, .06], [1.4, 0, .12], [2.9, 0, .05]], .24),
      w: .9
    })
  }),

  /** Double-take: quick glance, snap back wide-eyed Circle, narrow Sideways Pill, relax */
  doubletake: defEmote('Double take', 3.2, 4, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.75, pairEyes(['circle', { r: .168 }], ['circle', { r: .168 }]), .20],
      [1.75, F_WIDE, .28],
      [2.60, pairEyes(eyeShape || 'pill'), .32]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [
        [0, 0, .04],
        [0.18, .45, .06, 0, .18],
        [0.50, -.05, .06, 0, .18],
        [0.72, .48, .14, 0, .15],
        [1.75, .42, .04, 0, .24],
        [2.60, 0, .04, 0, .30]
      ]),
      w: .95
    })
  }),

  /** 3x3 Matrix sweep across both eyes -> Sideways Pill -> Pill */
  matrix: defEmote('Matrix sweep', 4.3, 3, {
    face: (t, e, eyeShape) => {
      const sweep = u => {
        const wave = xPos => .72 + .36 * Math.exp(-Math.pow(xPos - ((u - 1.0) * 2.4 - 1.2), 2) * 4.5);
        const lSc = [], rSc = [];
        for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) {
          lSc.push(wave(-0.8 + c * .25));
          rSc.push(wave(0.3 + c * .25));
        }
        return pairEyes(['matrix', { scales: lSc }], ['matrix', { scales: rSc }]);
      };
      return seqFace(e, [
        [0, F_PILL],
        [0.35, sweep, .38],
        [2.65, F_STACK, .34],
        [3.45, pairEyes(eyeShape || 'pill'), .36]
      ]);
    },
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .05], [.4, -.22, .08], [2.2, .22, .08], [2.7, 0, .05]], .35),
      w: .9
    })
  }),

  /** Pill splits into dual vertical equalizer bars that dance, then fuse back */
  equalize: defEmote('Equalize', 3.5, 3, {
    face: (t, e, eyeShape) => {
      const barsAnim = u => pairEyes(
        ['bars', { h1: .22 + .22 * Math.abs(Math.sin(u * 6.5)), h2: .22 + .22 * Math.abs(Math.cos(u * 6.5)) }],
        ['bars', { h1: .22 + .22 * Math.abs(Math.sin(u * 6.5 + 1)), h2: .22 + .22 * Math.abs(Math.cos(u * 6.5 + 1)) }]
      );
      return seqFace(e, [
        [0, F_PILL],
        [0.30, barsAnim, .32],
        [2.75, pairEyes(eyeShape || 'pill'), .34]
      ]);
    },
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .06], [.4, -.14, .10], [1.6, .14, .10], [2.75, 0, .06]], .34),
      w: .85
    })
  }),

  /** Asymmetric curious swap: (Circle | Sideways Pill) <-> (Sideways Pill | Circle) */
  curious: defEmote('Curious swap', 3.6, 3, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.28, pairEyes('circle', 'wide'), .30],
      [1.45, pairEyes('wide', 'circle'), .34],
      [2.65, F_CIRCLE, .28],
      [3.15, pairEyes(eyeShape || 'pill'), .30]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .05], [.3, -.26, .14, -.04], [1.45, .26, .14, .04], [2.65, 0, .10, 0], [3.15, 0, .05, 0]], .30),
      w: .9
    })
  }),

  /** Smooth 360 rim glance with chunky Circle eyes */
  orbit: defEmote('Orbit gaze', 3.4, 3, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.25, F_CIRCLE, .28],
      [2.75, pairEyes(eyeShape || 'pill'), .32]
    ]),
    motion: (t, e) => {
      const m = env(e, .2, .55, 2.45, 2.85), a = (e - .2) * 2.6;
      return { eyaw: Math.cos(a) * .46 * m, epitch: Math.sin(a) * .34 * m + .05 * (1 - m), w: .94 };
    }
  }),

  /** Suspicious horizontal-pill side-to-side glare (pure eye movement) */
  glare: defEmote('Sideways glare', 3.4, 3, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.25, F_WIDE, .28],
      [2.80, pairEyes(eyeShape || 'pill'), .32]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .03], [.32, -.52, -.02, 0, .32], [1.45, .52, -.02, 0, .42], [2.55, 0, .03, 0, .30]]),
      w: .96
    })
  }),

  /** Alternating crisp heavy winks */
  winkswap: defEmote('Wink swap', 2.8, 3, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_PILL],
      [0.22, pairEyes('arc', 'pill'), .22],
      [0.95, pairEyes('pill', 'arc'), .24],
      [1.75, F_ARC, .24],
      [2.35, pairEyes(eyeShape || 'pill'), .28]
    ]),
    motion: (t, e) => ({
      ...seqGaze(e, [[0, 0, .06], [.25, -.15, .12], [.98, .15, .12], [1.75, 0, .18], [2.35, 0, .06]], .22),
      w: .85
    })
  }),

  /** Weighty, calm slow blink into bold horizontal capsules */
  slowblink: defEmote('Slow blink', 2.2, 2, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, pairEyes(eyeShape || 'pill')],
      [0.25, F_SQUINT, .28],
      [0.55, F_WIDE, .30],
      [1.45, pairEyes(eyeShape || 'pill'), .38]
    ]),
    motion: (t, e) => ({ epitch: -.14 * env(e, .2, .6, 1.3, 1.8), w: .75 })
  }),

  /** Snappy Grok-style 3D spin emote with inquisitive arrival */
  twirl: defEmote('3D Twirl', 1.45, 2, {
    kicks: [[0, .42], [.72, .28]],
    face: (t, e, eyeShape) => seqFace(e, [
      [0, pairEyes(eyeShape || 'pill')],
      [0.52, F_CIRCLE, .22],
      [1.08, pairEyes(eyeShape || 'pill'), .28]
    ]),
    motion: (t, e) => {
      const u = clamp(e / .90, 0, 1);
      const sAng = u > 0 && u < 1 ? spinAngle(u) : 0;
      const bell = u > 0 && u < 1 ? Math.sin(u * Math.PI) : 0;
      return {
        spinYaw: sAng,
        spinEyeLead: .18 * bell,
        dy: -.052 * bell,
        bodyRoll: .12 * bell,
        epitch: .14 * bell + .06,
        w: .85
      };
    }
  }),

  /** Alive-mode sleep transition & wake */
  doze: defEmote('Dozing off', 4.4, 0, {
    face: (t, e, eyeShape) => seqFace(e, [
      [0, pairEyes(eyeShape || 'pill')],
      [0.5, F_SQUINT, .45],
      [1.4, F_WIDE, .45],
      [2.05, F_CIRCLE, .16],
      [2.55, F_SQUINT, .42],
      [3.35, F_REST, .48]
    ]),
    motion: (t, e) => e < 2.0
      ? { epitch: -.32 * (e / 2), bodyRoll: .08 * (e / 2), w: .9 }
      : e < 2.45
        ? { epitch: .12, dy: -.035 * pulse(e, 2.02, .3), w: .9 }
        : { epitch: -.34 * Math.min(1, (e - 2.45) / 1.4), bodyRoll: .10 * Math.min(1, (e - 2.45) / 1.4), eyaw: .08, w: .92 }
  }),
  wake: defEmote('Waking up', 1.5, 0, {
    kicks: [[0, .85]],
    face: (t, e, eyeShape) => seqFace(e, [
      [0, F_CIRCLE],
      [0.55, F_TALL, .22],
      [1.05, pairEyes(eyeShape || 'pill'), .28]
    ]),
    motion: (t, e) => ({
      dy: -.07 * pulse(e, 0, .32),
      ...seqGaze(e, [[0, 0, .14], [.35, -.32, .10, 0, .18], [.70, .32, .10, 0, .20], [1.05, 0, .06, 0, .24]]),
      w: .92
    })
  })
});

/* ---------- Optional Subtle Geometric Extras (off by default; enabled via `extras`) ---------- */
const tracePts = (c, pts) => {
  c.beginPath(); c.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) c.lineTo(pts[i][0], pts[i][1]);
  c.closePath();
};
const starPts = (x, y, r) => {
  const p = [];
  for (let k = 0; k < 8; k++) {
    const a = k * Math.PI / 4 - Math.PI / 2, rr = k % 2 ? r * .34 : r;
    p.push([x + Math.cos(a) * rr, y + Math.sin(a) * rr]);
  }
  return p;
};
const HEART_EX = heart(0, 0, .24);
const EXTRA = {
  dots: (R, t) => {
    const c = R.c; c.fillStyle = R.ink;
    for (let i = 0; i < 3; i++) {
      c.globalAlpha = R.a * (.25 + .75 * Math.max(0, Math.sin(t * 3 - i * .8)));
      c.beginPath(); c.arc(.66 + i * .22, -.98 - i * .1, .05 + i * .018, 0, TAU); c.fill();
    }
  },
  zzz: (R, t) => {
    const c = R.c; c.save(); c.setTransform(1, 0, 0, 1, 0, 0); c.fillStyle = R.ink;
    for (let i = 0; i < 3; i++) {
      const p = (t * .32 + i / 3) % 1;
      c.globalAlpha = R.a * Math.sin(p * Math.PI) * .85;
      c.font = `700 ${((.20 + p * .14) * R.k).toFixed(1)}px system-ui, sans-serif`;
      c.fillText('z', (.68 + p * .38) * R.k + R.W / 2, (-.68 - p * .52 + R.dy) * R.k + R.W / 2);
    }
    c.restore();
  },
  sparkle: (R, t, pal) => {
    const c = R.c; c.fillStyle = pal.spark; c.globalAlpha = R.a;
    for (const [x, y, r, ph] of [[.95, -.82, .15, 0], [-.96, -.52, .10, 1.7], [.68, -1.14, .08, 3.1]]) {
      tracePts(c, starPts(x, y, r * (.35 + .65 * Math.abs(Math.sin(t * 2.2 + ph))))); c.fill();
    }
  },
  heart: (R, t, pal) => {
    const c = R.c, p = (t * .48) % 1, ox = .86 + .05 * Math.sin(t * 3), oy = -.62 - p * .56;
    c.globalAlpha = R.a * Math.sin(p * Math.PI); c.fillStyle = pal.blush; c.beginPath();
    HEART_EX.forEach(([a, b], i) => i ? c.lineTo(ox + a, oy - b) : c.moveTo(ox + a, oy - b));
    c.closePath(); c.fill();
  },
  orbit: (R, t, pal) => {
    const c = R.c; c.fillStyle = pal.spark; c.globalAlpha = R.a;
    for (let i = 0; i < 3; i++) {
      const a = t * 2.5 + i * TAU / 3;
      if (Math.sin(a) > -.2) {
        c.beginPath(); c.arc(Math.cos(a) * .60, -1.04 + Math.sin(a) * .13, .055 + .018 * Math.sin(a), 0, TAU); c.fill();
      }
    }
  }
};
const BACK = {
  ring: (R, t, pal) => {
    const c = R.c, p = (t * .75) % 1;
    c.globalAlpha = R.a * (1 - p) * .65; c.strokeStyle = pal.color; c.lineWidth = .055;
    c.beginPath();
    const pts = R.bodyPts, sc = 1 + .30 * p;
    for (let i = 0; i < pts.length; i += 2) {
      const x = pts[i][0] * sc, y = pts[i][1] * sc + R.sh;
      i ? c.lineTo(x, y) : c.moveTo(x, y);
    }
    c.closePath(); c.stroke();
  }
};

/* ==========================================================================
   5. TURNTABLE 3D MATRIX, EXACT BITANGENT CAPSULE EXTRUSION & EYE PROJECTION
   ========================================================================== */

/** Grok-style 360° turn: near-constant angular speed (as measured in the reference), softened ends + tiny settle */
function spinAngle(u) {
  if (u <= 0 || u >= 1) return 0;
  const ease = u * u * (3 - 2 * u);
  const base = lerp(u, ease, 0.42);
  const over = u > 0.7 ? 0.012 * Math.sin((u - 0.7) / 0.3 * Math.PI) : 0;
  return TAU * (base + over);
}

function frame3D(yaw, pitch, roll) {
  const cp = Math.cos(pitch), f = [Math.sin(yaw) * cp, -Math.sin(pitch), Math.cos(yaw) * cp];
  const rl = Math.hypot(f[2], f[0]) || 1, r = [f[2] / rl, 0, -f[0] / rl];
  const u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]];
  const c = Math.cos(roll), s = Math.sin(roll);
  return {
    f,
    r: [r[0] * c + u[0] * s, r[1] * c + u[1] * s, r[2] * c + u[2] * s],
    u: [u[0] * c - r[0] * s, u[1] * c - r[1] * s, u[2] * c - r[2] * s]
  };
}

/**
 * Turntable orthonormal 3x3 rotation matrix `M = R_z(roll) * R_x(-pitch) * R_y(yaw)`
 * mapping body 3D space (+x right, +y down, +z front) into camera world space.
 * Spinning `yaw` 0..360° rotates cleanly around the vertical Y-axis without diagonal pitch precession!
 */
function mat3D(yaw, pitch, roll) {
  const cy = Math.cos(yaw), sy = Math.sin(yaw);
  const cp = Math.cos(pitch), sp = Math.sin(pitch);
  const cr = Math.cos(roll), sr = Math.sin(roll);
  return {
    m00:  cr * cy - sr * sy * sp,  m01: -sr * cp,  m02:  cr * sy + sr * cy * sp,
    m10:  sr * cy + cr * sy * sp,  m11:  cr * cp,  m12:  sr * sy - cr * cy * sp,
    m20: -sy * cp,                 m21:  sp,       m22:  cy * cp
  };
}

const MAX_SPH = MEDIAL_N * 2 + 4;
const MAX_SEG = MEDIAL_N * 6;
const _QX = new Float64Array(MAX_SPH);
const _QY = new Float64Array(MAX_SPH);
const _AK = new Float64Array(MAX_SPH);
const _AX = new Float64Array(MAX_SEG);
const _AY = new Float64Array(MAX_SEG);
const _BX = new Float64Array(MAX_SEG);
const _BY = new Float64Array(MAX_SEG);
const _DET = new Float64Array(MAX_SEG);

const jellyScale = (jx, th) =>
  1 + jx[0] * Math.cos(2 * th) + jx[1] * Math.sin(2 * th) +
  jx[2] * Math.cos(3 * th) + jx[3] * Math.sin(3 * th) +
  jx[4] * Math.cos(4 * th) + jx[5] * Math.sin(4 * th);

/**
 * Compute exact 2D perspective silhouette of the 3D Rounded Extrusion / Cushion under `M`:
 * - Exact analytical outer bitangents between consecutive 3D spine capsules eliminate all scalloping & bumps
 * - Clean telephoto perspective (`CAM_D = 15`) gives authentic 3D foreshortening without fisheye distortion
 */
function buildBodyContour(body, s, dxOff, dyOff, M, jx, jiggle, stride) {
  const out = [];
  const flat = jiggle ? clamp(jx[0], 0, .24) * .75 : 0;
  const fy = body.floorY - flat;

  if (body.mix) {
    // Morph: project both shapes under the same pose, then blend their outlines radially
    const [A, B, p] = body.mix;
    const pa = buildBodyContour(A, 1, 0, 0, M, jx, false, 1).pts;
    const pb = buildBodyContour(B, 1, 0, 0, M, jx, false, 1).pts;
    let ra0 = 0, rb0 = 0;
    for (let i = 0; i < BODY_N; i += stride) {
      const ux = RAY_DIRS[i][0], uy = RAY_DIRS[i][1];
      // Rays are nudged off exact outline vertices; a miss keeps the neighbouring radius
      const ca = Math.cos(1e-4), sa = Math.sin(1e-4), vx = ux * ca - uy * sa, vy = ux * sa + uy * ca;
      let ra = rayHit(pa, vx, vy), rb = rayHit(pb, vx, vy);
      if (ra <= 1e-6) ra = ra0; if (rb <= 1e-6) rb = rb0;
      ra0 = ra; rb0 = rb;
      const r = lerp(ra, rb, p);
      let x = ux * r * s, y = uy * r * s;
      if (jiggle) {
        const jr = jellyScale(jx, Math.atan2(y, x));
        x *= jr; y *= jr;
      }
      if (flat > 0 && y > fy) y = fy + (y - fy) * .28;
      out.push([x + dxOff, y + dyOff]);
    }
    return { pts: out, dx: dxOff, sh: dyOff };
  }

  if (body.solid) {
    const raw = solidOutline(body.solid, M, stride);
    for (let [x, y] of raw) {
      x *= s; y *= s;
      if (jiggle) {
        const jr = jellyScale(jx, Math.atan2(y, x));
        x *= jr; y *= jr;
      }
      if (flat > 0 && y > fy) y = fy + (y - fy) * .28;
      out.push([x + dxOff, y + dyOff]);
    }
    return { pts: out, dx: dxOff, sh: dyOff };
  }

  // Fast path: pure sphere (`circle`) or exact unrotated front view
  const isFront = Math.abs(M.m22 - 1) < 1e-5;
  if (body.isCircle || isFront) {
    const src = body.pts, n = src.length;
    const rc = M.m00, rs = M.m10;
    for (let i = 0; i < n; i += stride) {
      let x = src[i][0] * s, y = src[i][1] * s;
      if (!body.isCircle && isFront && (Math.abs(rs) > 1e-5 || Math.abs(rc - 1) > 1e-5)) {
        const nx = x * rc - y * rs, ny = x * rs + y * rc;
        x = nx; y = ny;
      }
      if (jiggle) {
        const jr = jellyScale(jx, Math.atan2(y, x));
        x *= jr; y *= jr;
      }
      if (flat > 0 && y > fy) y = fy + (y - fy) * .28;
      out.push([x + dxOff, y + dyOff]);
    }
    return { pts: out, dx: dxOff, sh: dyOff };
  }

  // Project ray origin `(poleX, poleY, 0)` (strictly inside the 3D solid at all 360°!)
  const px = body.poleX, py = body.poleY;
  const pz = M.m20 * px + M.m21 * py;
  const p0 = CAM_D / Math.max(2.0, CAM_D - pz);
  const ox0 = (M.m00 * px + M.m01 * py) * p0;
  const oy0 = (M.m10 * px + M.m11 * py) * p0;

  const spine = body.spine, N = spine.length;
  const slabH = body.slabH;
  const nL = slabH > 1e-4 ? 2 : 1;
  for (let l = 0; l < nL; l++) {
    const z = nL === 2 ? (l === 0 ? -slabH : slabH) : 0;
    const off = l * N;
    const mzX = M.m02 * z, mzY = M.m12 * z, mzZ = M.m22 * z;
    for (let m = 0; m < N; m++) {
      const sm = spine[m], bx = sm[0], by = sm[1], r = sm[2];
      const X = M.m00 * bx + M.m01 * by + mzX;
      const Y = M.m10 * bx + M.m11 * by + mzY;
      const Z = M.m20 * bx + M.m21 * by + mzZ;
      const persp = CAM_D / Math.max(2.0, CAM_D - Z);
      _QX[off + m] = X * persp - ox0;
      _QY[off + m] = Y * persp - oy0;
      _AK[off + m] = r * persp;
    }
  }

  // Precompute exact outer bitangent segments for perimeter & lateral 3D capsules
  let nSeg = 0;
  const addCapsule = (i, j) => {
    const x0 = _QX[i], y0 = _QY[i], x1 = _QX[j], y1 = _QY[j];
    const a0 = _AK[i], a1 = _AK[j], da = a0 - a1;
    const dx = x1 - x0, dy = y1 - y0, len = Math.hypot(dx, dy);
    if (len <= Math.abs(da) + 1e-6) return;
    const ux = dx / len, uy = dy / len, ct = da / len, st = Math.sqrt(Math.max(0, 1 - ct * ct));
    for (let sgn = -1; sgn <= 1; sgn += 2) {
      const nx = ux * ct + sgn * uy * st, ny = uy * ct - sgn * ux * st;
      // Keep only bitangents facing outward from ray origin (keeps both walls when edge-on at 90°!)
      if (x0 * nx + y0 * ny < -0.04 && x1 * nx + y1 * ny < -0.04) continue;
      const ax = x0 + nx * a0, ay = y0 + ny * a0;
      const bx = x1 + nx * a1, by = y1 + ny * a1;
      _AX[nSeg] = ax; _AY[nSeg] = ay;
      _BX[nSeg] = bx; _BY[nSeg] = by;
      _DET[nSeg] = ax * by - ay * bx;
      nSeg++;
    }
  };
  for (let l = 0; l < nL; l++) {
    const off = l * N;
    for (let m = 0; m < N; m++) addCapsule(off + m, off + ((m + 1) % N));
  }
  if (nL === 2) {
    for (let m = 0; m < N; m++) addCapsule(m, N + m);
  }

  const totalSph = N * nL;
  const coreT = body.coreR * p0;
  for (let i = 0; i < BODY_N; i += stride) {
    const ux = RAY_DIRS[i][0], uy = RAY_DIRS[i][1];
    let bestT = coreT;
    for (let k = 0; k < totalSph; k++) {
      const a = _AK[k], qx = _QX[k], qy = _QY[k];
      const perp = qx * uy - qy * ux;
      const disc = a * a - perp * perp;
      if (disc > 0) {
        const t = qx * ux + qy * uy + Math.sqrt(disc);
        if (t > bestT) bestT = t;
      }
    }
    for (let sg = 0; sg < nSeg; sg++) {
      const cA = _AX[sg] * uy - _AY[sg] * ux, cB = _BX[sg] * uy - _BY[sg] * ux;
      if ((cA >= 0) !== (cB >= 0)) {
        const t = _DET[sg] / (cA - cB);
        if (t > bestT) bestT = t;
      }
    }
    let x = (ox0 + ux * bestT) * s, y = (oy0 + uy * bestT) * s;
    if (jiggle) {
      const jr = jellyScale(jx, Math.atan2(y, x));
      x *= jr; y *= jr;
    }
    if (flat > 0 && y > fy) y = fy + (y - fy) * .28;
    out.push([x + dxOff, y + dyOff]);
  }
  return { pts: out, dx: dxOff, sh: dyOff };
}

const P3 = [0, 0, 0, 0];
/**
 * Project face-space point `(a, b)` flush onto the cambered 3D front face of `body`,
 * rotated by the exact same turntable 3D matrix `M` and telephoto lens `CAM_D` as the body!
 */
function projEye3D(a, b, localFr, M, body, faceScale) {
  if (body.mix) {
    const [A, B, p] = body.mix;
    projEye3D(a, b, localFr, M, A, faceScale);
    const x0 = P3[0], y0 = P3[1], f0 = P3[2], z0 = P3[3];
    projEye3D(a, b, localFr, M, B, faceScale);
    P3[0] = lerp(x0, P3[0], p); P3[1] = lerp(y0, P3[1], p);
    P3[2] = lerp(f0, P3[2], p); P3[3] = lerp(z0, P3[3], p);
    return P3;
  }
  if (body.solid) return projEyeSolid(a, b, localFr, M, body, faceScale);
  const zHalf = body.zHalf || 1;
  const camber = body.camber ?? 1;
  const kDepth = (CAM_D - zHalf) / CAM_D;
  const S = faceScale * body.fScale;
  const sa = a * S, sb = b * S, rho = Math.hypot(sa, sb);
  const f = localFr.f, r = localFr.r, u = localFr.u;

  let dx, dy, dz, xb, yb, zb;
  if (rho < 1e-6) {
    dx = f[0]; dy = f[1]; dz = Math.max(0, f[2]);
    const effRx = body.rx * clamp(1 + body.taperY * dy, 0.50, 1.18);
    xb = (body.ox + dx * effRx) * kDepth;
    yb = (body.oy + dy * body.ry) * kDepth;
    zb = zHalf * ((1 - camber) + camber * dz);
  } else {
    const k = Math.sin(rho) / rho, cr = Math.cos(rho), ra = sa * k, rb = sb * k;
    const tx = r[0] * ra + u[0] * rb, ty = r[1] * ra + u[1] * rb, tz = r[2] * ra + u[2] * rb;
    dx = f[0] * cr + tx; dy = f[1] * cr + ty; dz = f[2] * cr + tz;
    if (dz < 0) {
      const kl = Math.hypot(dx, dy) || 1;
      dx /= kl; dy /= kl; dz = 0;
    }
    const fDy = f[1] * cr;
    const effRx = body.rx * clamp(1 + body.taperY * fDy, 0.50, 1.18);
    xb = (body.ox + f[0] * cr * effRx + tx) * kDepth;
    yb = (body.oy + fDy * body.ry + ty) * kDepth;
    zb = zHalf * ((1 - camber) + camber * dz);
  }

  let X = M.m00 * xb + M.m01 * yb + M.m02 * zb;
  let Y = M.m10 * xb + M.m11 * yb + M.m12 * zb;
  let Z = M.m20 * xb + M.m21 * yb + M.m22 * zb;

  // Outward 3D surface normal of the cambered front face (pure sphere when `camber = 1`, crisp beveled face when `camber = 0.34`)
  const nbx = dx * camber, nby = dy * camber, nbz = Math.max(0.24, dz);
  const nLen = Math.hypot(nbx, nby, nbz) || 1;
  const Nx = (M.m00 * nbx + M.m01 * nby + M.m02 * nbz) / nLen;
  const Ny = (M.m10 * nbx + M.m11 * nby + M.m12 * nbz) / nLen;
  const Nz = (M.m20 * nbx + M.m21 * nby + M.m22 * nbz) / nLen;

  const vx = -X, vy = -Y, vz = CAM_D - Z, vLen = Math.hypot(vx, vy, vz) || 1;
  const facing = (vx * Nx + vy * Ny + vz * Nz) / vLen;

  if (facing < 0 && camber > 0.45) {
    const push = 1 - facing * 0.45 * camber;
    X *= push; Y *= push;
  }

  const persp = CAM_D / Math.max(2.0, CAM_D - Z);
  P3[0] = X * persp;
  P3[1] = Y * persp;
  P3[2] = facing;
  P3[3] = Z;
  return P3;
}

/**
 * Eyes on a true 3D solid: slide the face point across the front view (gaze), lift it onto the
 * solid's front surface via the heightfield, then rotate with the body. Near the rim the surface
 * normal turns away, so eyes foreshorten into crescents and wrap around the side naturally.
 */
function projEyeSolid(a, b, localFr, M, body, faceScale) {
  const S = faceScale * body.fScale;
  const sa = a * S, sb = b * S, rho = Math.hypot(sa, sb);
  const f = localFr.f, r = localFr.r, u = localFr.u;
  const k = rho < 1e-6 ? 1 : Math.sin(rho) / rho, cr = Math.cos(rho), ra = sa * k, rb = sb * k;
  const tx = r[0] * ra + u[0] * rb, ty = r[1] * ra + u[1] * rb;
  const fDy = f[1] * cr;
  const effRx = body.rx * clamp(1 + body.taperY * fDy, 0.50, 1.18);
  const xb = body.ox + f[0] * cr * effRx + tx;
  const yb = body.oy + fDy * body.ry + ty;
  const h = sampleHF(body.solid.hf, xb, yb), zb = h[0];
  const X = M.m00 * xb + M.m01 * yb + M.m02 * zb;
  const Y = M.m10 * xb + M.m11 * yb + M.m12 * zb;
  const Z = M.m20 * xb + M.m21 * yb + M.m22 * zb;
  const Nx = M.m00 * h[1] + M.m01 * h[2] + M.m02 * h[3];
  const Ny = M.m10 * h[1] + M.m11 * h[2] + M.m12 * h[3];
  const Nz = M.m20 * h[1] + M.m21 * h[2] + M.m22 * h[3];
  const vx = -X, vy = -Y, vz = CAM_D - Z, vLen = Math.hypot(vx, vy, vz) || 1;
  const persp = CAM_D / Math.max(2.0, CAM_D - Z);
  P3[0] = X * persp;
  P3[1] = Y * persp;
  P3[2] = (vx * Nx + vy * Ny + vz * Nz) / vLen;
  P3[3] = Z;
  return P3;
}

/**
 * Draw all eye & extra face cells onto `<canvas>`, clipped cleanly to the live 3D body silhouette!
 */
function drawFaceCells(c, localFr, M, rawFace, blinkAmt, pal, body, faceScale, warp, jx, jiggle, stride) {
  const face = blinkAmt > .002 ? {
    L: rawFace.L[0]?.noBlink ? rawFace.L : mixCluster(rawFace.L, F_WIDE.L, blinkAmt),
    R: rawFace.R[0]?.noBlink ? rawFace.R : mixCluster(rawFace.R, F_WIDE.R, blinkAmt),
    extras: rawFace.extras
  } : rawFace;
  const limb = 0.055 * (body.camber ?? 1);
  const fadeSpan = 0.11 + 0.08 * (body.camber ?? 1);
  const groups = [face.L, face.R, face.extras || []];
  for (const grp of groups) {
    if (!grp || !grp.length) continue;
    let gcx = 0, gcy = 0;
    for (const cell of grp) { gcx += cell.c[0]; gcy += cell.c[1]; }
    gcx /= grp.length; gcy /= grp.length;
    const grpCp = projEye3D(gcx, gcy, localFr, M, body, faceScale);
    const vis = clamp((grpCp[2] + limb) / fadeSpan, 0, 1);
    if (vis <= 0) continue;

    for (const cell of grp) {
      const op0 = cell.op ?? 1;
      if (op0 <= .01) continue;
      const P = cell.pts, n = P.length;
      c.beginPath();
      for (let i = 0; i < n; i += stride) {
        const p = projEye3D(P[i][0], P[i][1], localFr, M, body, faceScale);
        let X = p[0] * warp.s, Y = p[1] * warp.s;
        if (jiggle) {
          const r = jellyScale(jx, Math.atan2(Y, X));
          X *= r; Y *= r;
        }
        X += warp.dx;
        Y += warp.sh;
        i ? c.lineTo(X, Y) : c.moveTo(X, Y);
      }
      c.closePath();
      c.globalAlpha = op0 * vis;
      c.fillStyle = pal[cell.fill] || cell.fill;
      c.fill();
    }
  }
  c.globalAlpha = 1;
}

/* ==========================================================================
   6. SHARED POINTER, QUALITY GOVERNOR & SINGLE ANIMATION LOOP
   ========================================================================== */

const pointer = { x: 0, y: 0, active: false, t: 0 };
let listening = false, layoutVer = 0, frameNo = 0, clipSeq = 0;
function listen() {
  if (listening) return;
  listening = true;
  addEventListener('pointermove', e => {
    pointer.x = e.clientX; pointer.y = e.clientY; pointer.active = true; pointer.t = performance.now();
  }, { passive: true });
  document.documentElement.addEventListener('pointerleave', () => { pointer.active = false; });
  addEventListener('blur', () => { pointer.active = false; });
  const bump = () => { layoutVer++; };
  addEventListener('scroll', bump, { capture: true, passive: true });
  addEventListener('resize', bump, { passive: true });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { for (const o of live) o._colors(); });
}

const LEVELS = [{ stride: 1, dpr: 2 }, { stride: 2, dpr: 1.5 }, { stride: 2, dpr: 1 }];
const Q = { level: 0, auto: true, ema: 1, iv: 16.7, bad: 0, good: 0 };
function setLevel(l) { Q.level = clamp(l, 0, 2); Q.bad = Q.good = 0; for (const o of live) { o._fit(); o._sig = null; } }
function govern(cost, iv) {
  if (!Q.auto || iv > 120) return;
  Q.ema += (cost - Q.ema) * .08; Q.iv += (iv - Q.iv) * .08;
  const slow = Q.ema > 6.5 || Q.iv > 24, fast = Q.ema < 2.5 && Q.iv < 19;
  Q.bad = slow ? Q.bad + 1 : 0; Q.good = fast ? Q.good + 1 : 0;
  if (Q.bad > 45 && Q.level < 2) setLevel(Q.level + 1);
  else if (Q.good > 360 && Q.level > 0) setLevel(Q.level - 1);
}

const live = new Set();
let raf = 0, last = 0;
function loop(ms) {
  const iv = ms - last, dtRaw = Math.min(.08, Math.max(0, iv / 1000)), t = ms / 1000;
  last = ms; frameNo++;
  // Release stationary cursor after 1.5s so follow-mode orbs smoothly resume ambient idle life!
  if (pointer.active && ms - pointer.t > 1500) pointer.active = false;
  const t0 = performance.now(), half = Q.level >= 2, act = [];
  for (const o of live) if (o._visible && !o._static && o._cw) act.push(o);
  for (const o of act) {
    if ((o._target || (o._followMode() || o._alive) && pointer.active) && (o._rectVer !== layoutVer || frameNo % 30 === 0)) {
      o._rect = o.getBoundingClientRect(); o._rectVer = layoutVer;
    }
  }
  for (const o of act) {
    if (half && (frameNo + o._slot) & 1) { o._acc += dtRaw; continue; }
    const dt = Math.min(.08, dtRaw + o._acc); o._acc = 0;
    o._update(dt, t);
  }
  govern(performance.now() - t0, iv);
  raf = live.size ? requestAnimationFrame(loop) : 0;
}
const wake = () => { if (!raf && live.size) { last = performance.now(); raf = requestAnimationFrame(loop); } };

const io = new IntersectionObserver(es => {
  for (const e of es) { const o = e.target; o._visible = e.isIntersecting; if (o._visible) o._sig = null; }
}, { rootMargin: '120px' });
const ro = new ResizeObserver(es => { for (const e of es) e.target._resized(e.contentRect.width); });
const parseGaze = v => {
  if (!v) return null;
  const p = v.split(/[\s,]+/).map(Number);
  return p.length >= 2 && p.every(Number.isFinite) ? [p[0] * Math.PI / 180, p[1] * Math.PI / 180] : null;
};

const CANVAS_SCALE = 3.2 / 2.08;
let slots = 0;

const MKEYS = { dy: 0, s: 1, bodyRoll: 0, yawAdd: 0, spinYaw: 0, spinEyeLead: 0, eroll: 0, w: 0 };
function mixMotion(a, b, p) {
  const o = {};
  for (const [k, d] of Object.entries(MKEYS)) o[k] = lerp(a[k] ?? d, b[k] ?? d, p);
  for (const k of ['eyaw', 'epitch']) {
    const va = a[k] ?? a[k.slice(1)], vb = b[k] ?? b[k.slice(1)];
    if (va != null || vb != null) o[k] = lerp(va ?? vb, vb ?? va, p);
  }
  return o;
}

/* ==========================================================================
   7. <orb-avatar> WEB COMPONENT
   ========================================================================== */

const ATTRS = [
  'reaction', 'shape', 'eye-shape', 'mode', 'color', 'eye-color', 'size', 'follow',
  'shadow', 'extras', 'face-scale', 'morph', 'jelly', 'gaze', 'static', 'label',
  'alive', 'idle-motion', 'idle-time', 'sleep-after', 'emotes', 'particle-color', 'spark-color'
];

class OrbAvatar extends HTMLElement {
  static get observedAttributes() { return ATTRS; }

  /** Registered reactions */
  static get reactions() { return Object.keys(EX).filter(k => !EX[k].hidden); }
  static reactionLabel(name) { return (EX[name] || {}).label || name; }
  static defineReaction(name, def) {
    const faceFn = def.face || (def.feats ? (t, e) => {
      const list = def.feats(t, e), L = [], R = [], extras = [];
      for (const f of list) {
        const cell = makeCell(f.pts, f.c[0], f.c[1], f.fill || 'eye', { op: f.op, noBlink: f.fixed });
        if (f.key === 'L') L.push(cell);
        else if (f.key === 'R') R.push(cell);
        else extras.push({ ...cell, key: f.key });
      }
      return { L: L.length ? L : F_PILL.L, R: R.length ? R : F_PILL.R, extras };
    } : () => F_PILL);
    EX[name] = { label: name, ...def, face: faceFn };
  }

  /** Registered body silhouettes & custom SVG shape registration */
  static get bodyShapes() { return Object.keys(SHAPES); }
  static shapeLabel(name) { return (SHAPES[name] || {}).label || name; }
  static defineShape(name, svgOrPath, opts = {}) {
    const raw = typeof svgOrPath === 'string'
      ? (svgOrPath.trim().startsWith('<') ? resolveBodyShape(svgOrPath).pts : parseSVGPath(svgOrPath))
      : svgOrPath;
    if (raw && raw.length > 2) {
      if (opts.flat) regShape(name, opts.label || name, raw, opts);
      else SHAPES[name] = inflateBody(raw, { label: opts.label || name, ...opts });
      customShapeCache.delete(name);
      for (const o of live) if (o._shapeSpec === name) o._setBodyTarget(SHAPES[name], true);
    }
  }

  /** Registered solid heavy eye shapes */
  static get eyeShapes() { return Object.keys(EYE_SHAPES); }
  static defineEyeShape(name, builder) { EYE_SHAPES[name] = builder; STATIC_EYE_CACHE.clear(); }

  /** Autonomous eye-choreography emotes */
  static get emotes() { return Object.keys(EX).filter(k => EX[k].emote && EX[k].emote.weight > 0); }
  static defineEmote(name, { duration = 3, weight = 1, kicks = [], ...def }) {
    OrbAvatar.defineReaction(name, { ...def, hidden: true, emote: { dur: duration, weight, kicks } });
  }

  static get quality() { return Q.auto ? 'auto' : Q.level; }
  static set quality(v) { if (v === 'auto') { Q.auto = true; setLevel(0); } else { Q.auto = false; setLevel(+v || 0); } }
  static get qualityLevel() { return Q.level; }

  constructor() {
    super();
    const root = this.attachShadow({ mode: 'open' });
    root.innerHTML =
      '<style>:host{display:inline-block;position:relative;width:64px;aspect-ratio:1;flex:none;vertical-align:middle;line-height:0;-webkit-tap-highlight-color:transparent}' +
      `canvas{position:absolute;left:50%;top:50%;width:${(CANVAS_SCALE * 100).toFixed(2)}%;height:${(CANVAS_SCALE * 100).toFixed(2)}%;transform:translate(-50%,-50%);pointer-events:none}` +
      'i,slot{display:none}</style>' +
      '<canvas part="canvas"></canvas><i></i><slot name="shape"></slot><slot></slot>';
    this._canvas = root.querySelector('canvas');
    this._probe = root.querySelector('i');
    this._ctx = this._canvas.getContext('2d');
    this._slots = root.querySelectorAll('slot');
    for (const sl of this._slots) sl.addEventListener('slotchange', () => this._syncSlotShape());

    this._cw = 0; this._cssW = 0; this._sig = null; this._slot = slots++; this._acc = 0; this._rectVer = -1; this._inkAt = 0; this._colorVer = 0;
    this._expr = 'idle'; this._base = 'idle'; this._eyeShape = 'pill';
    this._shapeSpec = 'circle'; this._slottedSVG = null;
    this._bodyFrom = SHAPES.circle; this._bodyTo = SHAPES.circle; this._bodyCur = SHAPES.circle; this._btp = 1;

    this._override = null; this._overrideUntil = 0; this._overrideAt = 0; this._kickIdx = 0;
    this._customSeq = null;
    this._pokeAt = -9; this._pokes = [];
    this._alive = false; this._idleTime = 7; this._sleepAfter = 60; this._emoteList = null;
    this._lastAttn = performance.now() / 1000; this._nextEmote = this._lastAttn + 4; this._asleep = false; this._lastEmote = null; this._ptrSeen = 0;

    this._mode = 'drift'; this._idleMotion = 'lively'; this._ph = Math.random() * 20;
    // Ambient Idle Director state (pose-to-pose curiosity, rim peeks, head tilts & subtle eye micro-morphs)
    const now0 = performance.now() / 1000;
    this._idYaw = .16; this._idPitch = .10; this._idRoll = 0; this._idNext = now0 + 0.6 + Math.random() * 1.4;
    this._idFace = null; this._idFaceFrom = null; this._idFaceTp = 1; this._idStep = 0;
    this._raw = { color: '#f1efe9', eye: '#141418' };
    this._pal = { color: '#f1efe9', eye: '#141418', blush: '#ff6f91', spark: '#ffe08a' };
    this._ink = '#888';

    this._face = 1; this._morph = .38; this._jelly = .55; this._gaze = null;
    this._follow = false; this._shadow = false; this._extras = false; this._static = false; this._visible = true; this._target = null;

    // Dual-rate 3D springs: agile eye gaze (`_eyaw, _epitch, _eroll`) + plush 3D head volume (`_hyaw, _hpitch, _bRoll`)
    this._eyaw = .18; this._epitch = .12; this._eroll = 0; this._vey = 0; this._vep = 0; this._ver = 0;
    this._hyaw = .14; this._hpitch = .10; this._bRoll = 0; this._vhy = 0; this._vhp = 0; this._vbr = 0;
    this._init = false;

    // Face morph state
    this._tp = 1; this._fromFace = null; this._fromM = {}; this._curFace = F_PILL; this._m = {};
    this._jx = [0, 0, 0, 0, 0, 0]; this._jv = [0, 0, 0, 0, 0, 0];

    this._t = now0; this._nextBlink = now0 + 1.1 + Math.random() * 2.4; this._blinkAt = -9; this._dblBlinkAt = -9;
    this._spinAt = -9; this._spinCount = 0; this._spinStyle = 0; this._spinDir = 1; this._lastIdleSpin = now0;
  }

  connectedCallback() {
    listen(); live.add(this); io.observe(this); ro.observe(this);
    if (!this.hasAttribute('role')) this.setAttribute('role', 'img');
    this._syncSlotShape(false);
    this._colors(); this._aria(); this._update(0, performance.now() / 1000); wake();
  }
  disconnectedCallback() { live.delete(this); io.unobserve(this); ro.unobserve(this); }

  _syncSlotShape(animate = true) {
    let found = null;
    for (const sl of this._slots) {
      for (const el of sl.assignedElements({ flatten: true })) {
        if (el.tagName && el.tagName.toLowerCase() === 'svg') { found = el; break; }
      }
      if (found) break;
    }
    if (found !== this._slottedSVG) {
      this._slottedSVG = found;
      this._setBodyTarget(resolveBodyShape(this._shapeSpec, this._slottedSVG), animate);
    }
  }

  _setBodyTarget(nextBody, animate = true) {
    if (nextBody === this._bodyTo) return;
    if (animate && this._init && !this._static && this._morph > 0) {
      this._bodyFrom = this._bodyCur || this._bodyTo;
      this._btp = 0;
    } else {
      this._bodyFrom = this._bodyCur = nextBody;
      this._btp = 1;
    }
    this._bodyTo = nextBody;
    this._sig = null;
    wake();
  }

  attributeChangedCallback(n, _, v) {
    const now = performance.now() / 1000;
    switch (n) {
      case 'reaction': {
        const e = v && EX[v] && !EX[v].hidden ? v : 'idle', from = this._base;
        this._base = e; this._override = null; this._customSeq = null; this._asleep = false; this._lastAttn = now;
        this._show(e, true);
        if (from !== e) this.dispatchEvent(new CustomEvent('reactionchange', { detail: { from, to: e }, bubbles: true }));
        break;
      }
      case 'shape': {
        const prev = this._shapeSpec;
        this._shapeSpec = v || 'circle';
        this._setBodyTarget(resolveBodyShape(this._shapeSpec, this._slottedSVG), true);
        if (prev !== this._shapeSpec) this.dispatchEvent(new CustomEvent('shapechange', { detail: { from: prev, to: this._shapeSpec }, bubbles: true }));
        break;
      }
      case 'eye-shape': {
        const raw = (v || 'pill').trim(), parts = raw.split(/\s+/);
        const valid = parts.every(p => EYE_SHAPES[p]);
        const next = valid ? raw : 'pill', prev = this._eyeShape;
        this._eyeShape = next;
        if (prev !== next && this._init && !this._static) {
          this._fromFace = this._curFace; this._fromM = this._m || {}; this._tp = 0;
          wake();
          this.dispatchEvent(new CustomEvent('eyeshapechange', { detail: { from: prev, to: next }, bubbles: true }));
        }
        break;
      }
      case 'mode': this._mode = ['follow', 'wander', 'fixed', 'drift'].includes(v) ? v : 'drift'; break;
      case 'color': this._raw.color = v || '#f1efe9'; this._colors(); break;
      case 'eye-color': this._raw.eye = v || '#141418'; this._colors(); break;
      case 'size': this.style.width = v == null ? '' : (/^\d+(\.\d+)?$/.test(v) ? v + 'px' : v); break;
      case 'follow': this._follow = on(v); break;
      case 'shadow': this._shadow = on(v); break;
      case 'extras': this._extras = on(v); break;      // Clean & geometric by default (opt-in extras)
      case 'face-scale': {
        // Accept v2 scale (default 1.0) seamlessly; if someone passes legacy ~1.6, normalize gently or direct multiplier
        this._face = clamp(num(v, 1), 0.4, 2.2);
        break;
      }
      case 'morph': this._morph = Math.max(0, num(v, .38)); break;
      case 'jelly': this._jelly = clamp(num(v, .55), 0, 1); break;
      case 'gaze': this._gaze = parseGaze(v); break;
      case 'static': this._static = on(v); break;
      case 'alive': this._alive = on(v); this._nextEmote = now + this._idleTime * (.5 + Math.random() * .6); this._lastAttn = now; break;
      case 'idle-motion': this._idleMotion = ['lively', 'calm', 'off'].includes(v) ? v : 'lively'; break;
      case 'idle-time': this._idleTime = Math.max(.5, num(v, 7)); this._nextEmote = now + this._idleTime * (.5 + Math.random() * .6); break;
      case 'sleep-after': this._sleepAfter = Math.max(0, num(v, 60)); break;
      case 'particle-color': case 'spark-color': this._colors(); break;
      case 'emotes': this._emoteList = v ? v.split(/[\s,]+/).filter(Boolean) : null; break;
    }
    this._sig = null; this._aria();
    if (this.isConnected && (this._static || !raf)) this._update(0, now);
  }

  /* ---------- Public JavaScript API ---------- */
  get reaction() { return this._base; }
  set reaction(v) { this.setAttribute('reaction', v); }
  get shape() { return this._shapeSpec; }
  set shape(v) { this.setAttribute('shape', v); }
  get eyeShape() { return this._eyeShape; }
  set eyeShape(v) { this.setAttribute('eye-shape', v); }
  get mode() { return this._mode; }
  set mode(v) { this.setAttribute('mode', v); }

  react(name) { this.reaction = name; return this; }
  setShape(shape) { this.shape = shape; return this; }
  morphEyes(eyeShape) {
    this._customSeq = null;
    this._override = null;
    if (this._base !== 'idle') {
      this._fromFace = this._curFace; this._fromM = this._m || {};
      this.setAttribute('reaction', 'idle');
    }
    this.eyeShape = eyeShape;
    return this;
  }

  /**
   * Play a custom sequence of eye shapes & gazes on the fly!
   * Example: `orb.sequence(['pill', 'circle', 'grid', 'wide', 'pill'], { stepDuration: 0.75 })`
   * Or detailed steps: `[{ eyes: ['circle', 'wide'], gaze: [20, 10], hold: 0.8 }, ...]`
   */
  sequence(steps, { stepDuration = 0.72, morphDuration = 0.34 } = {}) {
    if (!Array.isArray(steps) || !steps.length || this._static) return this;
    const now = performance.now() / 1000;
    const fSteps = [], gStops = [];
    let tCursor = 0;
    for (const st of steps) {
      const dur = (typeof st === 'object' && !Array.isArray(st) && st.hold != null) ? st.hold : stepDuration;
      let face;
      if (typeof st === 'string') face = pairEyes(st);
      else if (Array.isArray(st)) face = pairEyes(st[0], st[1]);
      else {
        const es = st.eyes || 'pill';
        face = Array.isArray(es) ? pairEyes(es[0], es[1]) : pairEyes(es);
      }
      fSteps.push([tCursor, face, morphDuration]);
      const gz = (typeof st === 'object' && !Array.isArray(st) && st.gaze) ? st.gaze : [0, 4];
      gStops.push([tCursor, gz[0] * Math.PI / 180, gz[1] * Math.PI / 180, (gz[2] || 0) * Math.PI / 180, morphDuration]);
      tCursor += dur;
    }
    this._asleep = false;
    this._customSeq = {
      start: now,
      until: now + tCursor,
      face: e => seqFace(e, fSteps, morphDuration),
      motion: e => ({ ...seqGaze(e, gStops, morphDuration), w: .92 })
    };
    this._fromFace = this._curFace; this._fromM = this._m || {}; this._tp = 0;
    this._lastAttn = now;
    wake();
    return this;
  }

  poke(force = 1, { react = true } = {}) {
    const j = this._jelly * force, now = performance.now() / 1000;
    this._jv[0] += 3.1 * j; this._jv[2] += (Math.random() - .5) * 2.2 * j; this._jv[3] += (Math.random() - .5) * 2.2 * j;
    this._lastAttn = now;
    if (react && !this._static) {
      if (this._asleep) { this._asleep = false; this._play('wake', now); }
      else {
        this._pokes = this._pokes.filter(p => now - p < 1.3); this._pokes.push(now);
        const n = this._pokes.length, e = n >= 3 ? 'dizzy' : n === 2 ? 'giggle' : 'surprised';
        this._pokeAt = now; this._override = e; this._overrideAt = now; this._kickIdx = 0;
        this._overrideUntil = now + (e === 'dizzy' ? 1.85 : e === 'giggle' ? 1.15 : .9);
        this._show(e, false);
        this.dispatchEvent(new CustomEvent('poke', { detail: { count: n, reaction: e }, bubbles: true }));
      }
    }
    wake(); return this;
  }

  _triggerSpin(now, style, dir = 1) {
    this._spinAt = now;
    this._spinStyle = style;
    this._spinDir = dir;
    this._lastAttn = now;
    wake();
  }

  spin(style) {
    const now = performance.now() / 1000;
    const st = style === 'tilt' ? 1 : style === 'turntable' ? 0 : (this._spinCount++ % 2);
    const dir = style === 'reverse' ? -1 : 1;
    this._triggerSpin(now, st, dir);
    return this;
  }
  blink() { this._blinkAt = performance.now() / 1000; wake(); return this; }
  emote(name) {
    if (EX[name] && EX[name].emote && !this._static) {
      this._asleep = false; this._customSeq = null; this._play(name, performance.now() / 1000);
    }
    return this;
  }
  sleep() { return this.emote('doze'); }
  wakeUp() {
    const now = performance.now() / 1000;
    if (this._asleep) { this._asleep = false; this._play('wake', now); }
    this._lastAttn = now; return this;
  }
  get asleep() { return this._asleep; }
  lookAt(x, y) { this._target = (x == null || y == null) ? null : { x, y }; this._rectVer = -1; wake(); return this; }

  /** Crisp standalone SVG string of the current 3D silhouette, perspective pose, and multi-cell eyes */
  toSVG({ size = 512 } = {}) {
    const body = this._bodyCur || SHAPES.circle;
    const hRatio = body.isCircle ? .68 : .54;
    const yaw = this._eyaw || .18, pitch = this._epitch || .12, bodyRoll = this._bRoll || 0;
    const headYaw = this._hyaw ?? (yaw * hRatio), headPitch = this._hpitch ?? (pitch * hRatio);
    const M = mat3D(headYaw, headPitch, bodyRoll);
    const localFr = frame3D(yaw - headYaw, pitch - headPitch, this._eroll || 0);
    const contour = buildBodyContour(body, 1, 0, 0, M, this._jx, false, 1);
    const face = this._curFace || pairEyes(this._eyeShape), pal = this._pal;
    const clipId = 'orb-clip-' + (++clipSeq);
    let bd = '';
    let ext = 1.12;
    contour.pts.forEach(([x, y], i) => { bd += (i ? 'L' : 'M') + f4(x) + ' ' + f4(y); ext = Math.max(ext, Math.abs(x) + .04, Math.abs(y) + .04); });
    bd += 'Z';

    const limb = 0.055 * (body.camber ?? 1);
    const fadeSpan = 0.11 + 0.08 * (body.camber ?? 1);
    let fd = '';
    for (const grp of [face.L, face.R, face.extras || []]) {
      if (!grp || !grp.length) continue;
      let gcx = 0, gcy = 0;
      for (const cell of grp) { gcx += cell.c[0]; gcy += cell.c[1]; }
      gcx /= grp.length; gcy /= grp.length;
      const grpCp = projEye3D(gcx, gcy, localFr, M, body, this._face);
      const vis = clamp((grpCp[2] + limb) / fadeSpan, 0, 1);
      if (vis <= 0) continue;
      for (const cell of grp) {
        const op0 = cell.op ?? 1; if (op0 <= .01) continue;
        let d = '';
        cell.pts.forEach(([a, b], i) => {
          const p = projEye3D(a, b, localFr, M, body, this._face);
          d += (i ? 'L' : 'M') + f4(p[0]) + ' ' + f4(p[1]);
        });
        const op = op0 * vis;
        fd += `<path d="${d}Z" fill="${pal[cell.fill] || cell.fill}"${op < .999 ? ` opacity="${op.toFixed(2)}"` : ''}/>`;
      }
    }
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${f4(-ext)} ${f4(-ext)} ${f4(2 * ext)} ${f4(2 * ext)}" width="${size}" height="${size}">` +
      `<defs><clipPath id="${clipId}"><path d="${bd}"/></clipPath></defs>` +
      `<path d="${bd}" fill="${pal.color}"/>` +
      `<g clip-path="url(#${clipId})">${fd}</g></svg>`;
  }

  /* ---------- Internals ---------- */
  _play(name, t) {
    const em = EX[name].emote || {};
    this._override = name; this._overrideAt = t; this._overrideUntil = t + (em.dur ?? 2); this._kickIdx = 0; this._lastEmote = name;
    this._show(name, false); wake();
    this.dispatchEvent(new CustomEvent('emote', { detail: { name }, bubbles: true }));
  }

  _pickEmote() {
    const pool = Object.keys(EX).filter(k => {
      const em = EX[k].emote;
      return em && em.weight > 0 && k !== this._lastEmote && (!this._emoteList || this._emoteList.includes(k));
    });
    let r = Math.random() * pool.reduce((a, k) => a + EX[k].emote.weight, 0);
    for (const k of pool) { r -= EX[k].emote.weight; if (r <= 0) return k; }
    return pool[0] || null;
  }

  _life(t) {
    if (pointer.active && pointer.t > this._ptrSeen && this._rect) {
      this._ptrSeen = pointer.t; const b = this._rect;
      if (Math.hypot(pointer.x - b.left - b.width / 2, pointer.y - b.top - b.height / 2) < Math.max(140, b.width * 2)) {
        this._lastAttn = t;
        if (this._asleep) { this._asleep = false; this._play('wake', t); }
      }
    }
    if (this._base !== 'idle' || this._override || this._customSeq) return;
    if (this._sleepAfter > 0 && t - this._lastAttn > this._sleepAfter) this._play('doze', t);
    else if (t > this._nextEmote) {
      const k = this._pickEmote();
      if (k) this._play(k, t); else this._nextEmote = t + this._idleTime;
    }
  }

  _followMode() { return this._mode === 'follow' || (this._follow && this._mode === 'drift'); }
  _aria() { if (this.isConnected) this.setAttribute('aria-label', this.getAttribute('label') || OrbAvatar.reactionLabel(this._base)); }

  _colors() {
    if (!this.isConnected) return;
    const pr = this._probe;
    const resolve = v => { pr.style.color = ''; pr.style.color = v; return getComputedStyle(pr).color || v; };
    for (const k of ['color', 'eye']) this._pal[k] = resolve(this._raw[k]);
    const cs = getComputedStyle(this);
    const pick = (attr, prop, fallback) => { const v = this.getAttribute(attr) || cs.getPropertyValue(prop).trim(); return v ? resolve(v) : fallback; };
    this._ink = pick('particle-color', '--orb-particle-color', cs.color);
    this._pal.spark = pick('spark-color', '--orb-spark-color', '#ffe08a');
    this._colorVer++; this._sig = null;
  }

  _resized(w) { this._cssW = w; this._fit(); this._sig = null; if (this._static || !raf) this._update(0, performance.now() / 1000); }
  _fit() {
    const dpr = Math.min(window.devicePixelRatio || 1, LEVELS[Q.level].dpr);
    const px = Math.max(0, Math.round(this._cssW * CANVAS_SCALE * dpr));
    if (px !== this._cw) { this._canvas.width = this._canvas.height = px; this._cw = px; this._sig = null; }
  }

  _show(e, kick = true) {
    if (e === this._expr && !this._customSeq) return;
    const from = this._expr;
    this._colors();
    if (this._curFace && !this._static && this._morph > 0) {
      this._fromFace = this._curFace; this._fromM = this._m || {}; this._fromExpr = from; this._tp = 0;
    } else {
      this._tp = 1;
    }
    this._expr = e;
    if (kick && from !== e && this._init && !this._static) {
      const j = this._jelly * .75;
      this._jv[0] += 1.9 * j; this._jv[2] += (Math.random() - .5) * 1.4 * j; this._jv[5] += (Math.random() - .5) * 1.1 * j;
    }
    wake();
  }

  /**
   * Grokbot-inspired Ambient Idle Director:
   * Even when nothing external is happening, the orb behaves like a curious desk companion —
   * holding calm poses, cocking its head, peeking all the way to the 3D rim, gazing up at the ceiling,
   * and subtly shifting eye shapes (inquisitive circles, sideways squints, geometric micro-morphs).
   */
  _stepIdleDirector(t, dt, allowEyeShifts) {
    const g = this._gaze || [.14, .08];
    if (this._idleMotion === 'off') return { yaw: g[0], pitch: g[1], roll: 0, face: null };

    if (this._idFaceTp < 1) {
      this._idFaceTp = Math.min(1, this._idFaceTp + dt / Math.max(.22, this._morph * .9));
    }

    if (t >= this._idNext) {
      this._idStep++;
      const calmMode = this._idleMotion === 'calm';
      const r = Math.random();
      const sgn = () => (Math.random() < .5 ? -1 : 1);
      let nextFace = null;

      if (calmMode) {
        this._idYaw = g[0] + (Math.random() * 2 - 1) * .38;
        this._idPitch = g[1] + (Math.random() * 2 - 1) * .24;
        this._idRoll = (Math.random() * 2 - 1) * .10;
        this._idNext = t + 1.8 + Math.random() * 2.4;
      } else if (r < 0.24) {
        // 1. Calm front/near check-in (often paired with a double-blink)
        this._idYaw = g[0] + (Math.random() * 2 - 1) * .24;
        this._idPitch = g[1] + (Math.random() * 2 - 1) * .16;
        this._idRoll = (Math.random() * 2 - 1) * .08;
        this._idNext = t + 1.4 + Math.random() * 1.9;
        if (Math.random() < .45) { this._blinkAt = t + .12; this._dblBlinkAt = t + .33; }
      } else if (r < 0.46) {
        // 2. Deep 3D Rim Peek / Over-the-shoulder glance (eyes wrap right onto the curved edge!)
        const dir = sgn();
        this._idYaw = dir * (.82 + Math.random() * .44);
        this._idPitch = -.34 + Math.random() * .68;
        this._idRoll = dir * (.10 + Math.random() * .14);
        this._idNext = t + 0.95 + Math.random() * 1.35;
        if (allowEyeShifts && this._eyeShape === 'pill' && Math.random() < .32) {
          nextFace = pairEyes(['squint', { w: .27, h: .18 }]);
        }
      } else if (r < 0.66) {
        // 3. Cheeky Head Tilt + Inquisitive Curious Gaze
        const dir = sgn();
        this._idYaw = dir * (.18 + Math.random() * .38);
        this._idPitch = .08 + Math.random() * .28;
        this._idRoll = dir * (.18 + Math.random() * .16);
        this._idNext = t + 1.25 + Math.random() * 1.65;
        if (allowEyeShifts && this._eyeShape === 'pill' && Math.random() < .48) {
          // Asymmetric Grok-style inquisitive circles (one slightly larger!)
          const bigL = dir < 0;
          nextFace = pairEyes(['circle', { r: bigL ? .166 : .134 }], ['circle', { r: bigL ? .134 : .166 }]);
        }
      } else if (r < 0.82) {
        // 4. Sky / Ceiling Daydream (foreshortens vertical pills into wide top ovals & rounds 3D belly)
        const dir = sgn();
        this._idYaw = dir * Math.random() * .42;
        this._idPitch = .62 + Math.random() * .32;
        this._idRoll = dir * (.06 + Math.random() * .10);
        this._idNext = t + 1.15 + Math.random() * 1.5;
      } else if (r < 0.90) {
        // 5. Quick Micro-Saccade Dart (eye-first snap nearby)
        this._idYaw = clamp(this._idYaw + sgn() * (.32 + Math.random() * .28), -1.1, 1.1);
        this._idPitch = clamp(this._idPitch + (Math.random() - .5) * .34, -.45, .65);
        this._idRoll = clamp(this._idYaw * .15, -.22, .22);
        this._idNext = t + 0.55 + Math.random() * 0.75;
        if (allowEyeShifts && this._eyeShape === 'pill' && Math.random() < .35) {
          nextFace = F_WIDE;
        }
      } else if (r < 0.96 || t - this._lastIdleSpin < 15) {
        // 6. Subtle Geometric Signature Micro-Morph (grid or circle beat, then back to base eyeShape)
        this._idYaw = (Math.random() * 2 - 1) * .32;
        this._idPitch = .06 + Math.random() * .18;
        this._idRoll = (Math.random() * 2 - 1) * .12;
        this._idNext = t + 1.2 + Math.random() * 1.1;
        if (allowEyeShifts && this._eyeShape === 'pill') {
          nextFace = Math.random() < .55 ? F_GRID : F_CIRCLE;
        }
      } else {
        // 7. Spontaneous Mac-Notch 3D Whip-Spin (turntable or playful tilted pebble spin)
        const dir = sgn();
        this._lastIdleSpin = t;
        this._triggerSpin(t + 0.04, Math.random() < .55 ? 0 : 1, dir);
        this._idYaw = dir * .16;
        this._idPitch = .10;
        this._idRoll = dir * .06;
        this._idNext = t + 1.45 + Math.random() * 1.4;
      }

      const curIdleFace = this._idFace || pairEyes(this._eyeShape || 'pill');
      const targetIdleFace = nextFace || pairEyes(this._eyeShape || 'pill');
      if (this._idFace !== nextFace) {
        this._idFaceFrom = this._idFaceTp < 1 && this._idFaceFrom
          ? mixFaces(this._idFaceFrom, curIdleFace, this._idFaceTp)
          : curIdleFace;
        this._idFace = nextFace;
        this._idFaceTp = 0;
      }
      void targetIdleFace;
    }

    let face = null;
    if (allowEyeShifts && (this._idFace || this._idFaceTp < 1)) {
      const toF = this._idFace || pairEyes(this._eyeShape || 'pill');
      const fromF = this._idFaceFrom || pairEyes(this._eyeShape || 'pill');
      face = this._idFaceTp < 1 ? mixFaces(fromF, toF, this._idFaceTp) : this._idFace;
    }

    // Layer subtle organic micro-drift onto held pose so it never freezes dead-still
    const ph = this._ph;
    return {
      yaw: this._idYaw + .05 * Math.sin(t * 1.1 + ph),
      pitch: this._idPitch + .04 * Math.cos(t * 1.35 + ph * 1.4),
      roll: this._idRoll + .025 * Math.sin(t * 0.95 + ph * 2),
      face
    };
  }

  _update(dt, t) {
    this._t = t;
    const st = this._static, calm = RMQ.matches || st, dur = RMQ.matches ? .18 : this._morph;
    this._tp = (st || dur <= 0) ? 1 : Math.min(1, this._tp + dt / dur);
    this._btp = (st || dur <= 0) ? 1 : Math.min(1, this._btp + dt / (dur * 1.15));
    this._bodyCur = this._btp < 1 ? mixBody(this._bodyFrom, this._bodyTo, easeMorph(this._btp)) : this._bodyTo;

    if (!st && t > this._nextBlink) {
      this._blinkAt = t;
      const dbl = Math.random() < .24;
      if (dbl) this._dblBlinkAt = t + .21;
      this._nextBlink = t + 2.1 + Math.random() * 3.6;
    }
    if (!st && this._dblBlinkAt > 0 && t >= this._dblBlinkAt) {
      this._blinkAt = t;
      this._dblBlinkAt = -9;
    }

    if (this._customSeq && t > this._customSeq.until) {
      this._customSeq = null;
      this._fromFace = this._curFace; this._fromM = this._m || {}; this._tp = 0;
    }
    if (this._override && t > this._overrideUntil) {
      const ended = this._override; this._override = null;
      if (ended === 'doze') {
        this._asleep = true; this._override = 'sleeping'; this._overrideAt = t; this._overrideUntil = Infinity;
        this._show('sleeping', false);
      } else {
        this._show(this._base, false);
        this._nextEmote = t + this._idleTime * (.75 + Math.random() * .85);
      }
    }
    if (this._alive && !st) this._life(t);

    if (this._override) {
      const kicks = (EX[this._override].emote || {}).kicks || [], e = t - this._overrideAt;
      while (this._kickIdx < kicks.length && e >= kicks[this._kickIdx][0]) {
        const j = this._jelly * kicks[this._kickIdx][1];
        this._jv[0] += 2.6 * j; this._jv[2] += (Math.random() - .5) * 1.8 * j;
        this._kickIdx++;
      }
    }

    const mode = this._followMode() ? 'follow' : this._mode, fixed = mode === 'fixed' && !this._override && !this._customSeq;
    const ex = EX[this._expr] || EX.idle;
    const lt = calm ? 0 : t + this._ph, ft = st ? 0 : t + this._ph;
    const p = easeMorph(this._tp);
    const since = this._customSeq ? (t - this._customSeq.start) : (this._override ? t - this._overrideAt : t - this._pokeAt);
    this._since = since;

    const rawM = this._customSeq ? this._customSeq.motion(since) : ((ex.motion && !fixed) ? ex.motion(lt, since) : {});
    const m = this._tp < 1 ? mixMotion(fixed ? {} : this._fromM, rawM, p) : rawM;
    this._m = m;

    // Base gaze from active pointer tracking OR Grokbot-style Ambient Idle Director
    let ly, lp, lroll = 0, idleCustomFace = null;
    const g = this._gaze || [.14, .08];
    const look = this._target || (mode === 'follow' && pointer.active ? pointer : null);
    if (look && this._rect) {
      const b = this._rect, cx = b.left + b.width / 2, cy = b.top + b.height / 2, D = Math.max(250, b.width * 1.65);
      ly = clamp(Math.atan((look.x - cx) / D) * 1.25, -1.18, 1.18);
      lp = clamp(Math.atan((cy - look.y) / D) * 1.22, -.92, .92);
      lroll = clamp(ly * 0.18, -.24, .24);
      // Clear temporary idle eye micro-shift smoothly when user engages cursor
      if (this._idFace) { this._idFaceFrom = this._curFace; this._idFace = null; this._idFaceTp = 0; }
      this._idNext = t + 0.4 + Math.random() * 0.6;
    } else if (!calm && mode !== 'fixed') {
      const allowEyeShifts = this._expr === 'idle' && !this._override && !this._customSeq;
      const id = this._stepIdleDirector(t, dt, allowEyeShifts);
      ly = id.yaw; lp = id.pitch; lroll = id.roll; idleCustomFace = id.face;
    } else {
      ly = g[0]; lp = g[1]; lroll = 0;
    }

    const tgtOf = q => {
      const w = q.w ?? 0, qy = q.eyaw ?? q.yaw, qp = q.epitch ?? q.pitch;
      const ey = ly + ((qy ?? ly) - ly) * w;
      const ep = lp + ((qp ?? lp) - lp) * w;
      const br = q.bodyRoll != null || q.roll != null ? lerp(lroll, q.bodyRoll ?? q.roll, Math.max(w, .7)) : lroll;
      return [ey, ep, q.eroll ?? 0, br];
    };
    let T = tgtOf(rawM);
    if (this._tp < 1) {
      const A = tgtOf(this._fromM);
      T = T.map((v, i) => lerp(A[i], v, p));
    }

    const hR = b => b.isCircle ? .68 : .54;
    const hRatio = this._btp < 1 ? lerp(hR(this._bodyFrom), hR(this._bodyTo), easeMorph(this._btp)) : hR(this._bodyTo);
    if (st || !this._init) {
      this._eyaw = T[0]; this._epitch = T[1]; this._eroll = T[2];
      this._hyaw = T[0] * hRatio; this._hpitch = T[1] * hRatio; this._bRoll = T[3];
      this._init = true;
    } else {
      // Agile eye spring (leads turns crisply) + plush 3D head spring (rotates solid in 3D perspective!)
      const stepEye = (x, v, goal) => { v += (goal - x) * 165 * dt; v *= Math.exp(-19 * dt); return [x + v * dt, v]; };
      const stepHead = (x, v, goal) => { v += (goal - x) * 68 * dt; v *= Math.exp(-11.5 * dt); return [x + v * dt, v]; };
      [this._eyaw, this._vey] = stepEye(this._eyaw, this._vey, T[0]);
      [this._epitch, this._vep] = stepEye(this._epitch, this._vep, T[1]);
      [this._eroll, this._ver] = stepEye(this._eroll, this._ver, T[2]);
      [this._hyaw, this._vhy] = stepHead(this._hyaw, this._vhy, T[0] * hRatio);
      [this._hpitch, this._vhp] = stepHead(this._hpitch, this._vhp, T[1] * hRatio);
      [this._bRoll, this._vbr] = stepHead(this._bRoll, this._vbr, T[3]);
    }

    this._jellyStep(dt);

    // Evaluate target face & smooth multi-cell morph
    const targetFace = this._customSeq
      ? this._customSeq.face(since)
      : (idleCustomFace || ex.face(ft, since, this._eyeShape));
    this._curFace = (this._tp < 1 && this._fromFace) ? mixFaces(this._fromFace, targetFace, this._tp) : targetFace;

    const ambientOn = !calm && mode !== 'fixed' && this._idleMotion !== 'off';
    const spinning = (t - this._spinAt) >= 0 && (t - this._spinAt) < 1.05;
    const isAnim = ambientOn || spinning || !!this._customSeq || (ex.face.length > 0 && !ex.useEyeShape) || this._tp < 1 || this._btp < 1;
    this._render(p, m, calm, isAnim, fixed);
  }

  _jellyStep(dt) {
    const j = this._jelly, x = this._jx, v = this._jv;
    if (this._static) { for (let i = 0; i < 6; i++) x[i] = v[i] = 0; return; }
    const w = lerp(25, 14.5, j), D = lerp(11.5, 4.0, j), n = Math.ceil(dt * 60 - 1e-6), h = n ? dt / n : 0;
    for (let s = 0; s < n; s++) {
      for (let i = 0; i < 6; i++) {
        const k = i > 1 ? w * 1.32 : w;
        v[i] += (-k * k * x[i] - D * v[i]) * h;
        x[i] = clamp(x[i] + v[i] * h, -.28, .28);
      }
    }
  }

  _render(p, m, calm, dyn, fixed) {
    const c = this._ctx, W = this._cw;
    if (!W) return;
    const t = this._t, ex = EX[this._expr] || EX.idle, pal = this._pal, jx = this._jx, body = this._bodyCur;

    // Snappy Grok-style 3D spin (`turntable` level whip-spin + `tilt` buoyant 3D pebble spin)
    const spinDur = this._spinStyle === 1 ? .82 : .72;
    const sp = (t - this._spinAt) / spinDur;
    const inSpin = sp >= 0 && sp < 1;
    const sBell = inSpin ? Math.sin(sp * Math.PI) : 0;
    const sDir = this._spinDir || 1;
    const spinYaw = (inSpin ? sDir * spinAngle(sp) : 0) + (m.spinYaw || 0);
    const spinLead = (inSpin ? sDir * .18 * sBell : 0) + (m.spinEyeLead || 0);
    const spinPitch = inSpin
      ? (this._spinStyle === 1 ? lerp(this._hpitch, .46, sBell * .9) : lerp(this._hpitch, .26, sBell * .85))
      : this._hpitch;
    // Grok-style: the bot spins around its own tilted axis (pitched back so the base reads from below)
    const spinRollAdd = inSpin ? sDir * (this._spinStyle === 1 ? .24 : .12) * sBell : 0;
    const spinDy = inSpin ? -(this._spinStyle === 1 ? .062 : .038) * sBell : 0;

    const yaw = this._eyaw + spinYaw + spinLead + (m.yawAdd || 0);
    const pitch = clamp(inSpin ? lerp(this._epitch, spinPitch * 1.15, sBell * .8) : this._epitch, -1.25, 1.25);
    const headYaw = this._hyaw + spinYaw + (m.yawAdd || 0) * .7;
    const headPitch = clamp(spinPitch, -1.15, 1.15);
    const bodyRoll = (calm ? 0 : this._bRoll) + spinRollAdd;
    const eyeRoll = this._eroll;

    // Blink envelope: smooth symmetric cushion into heavy capsule
    const bl = (t - this._blinkAt) / .155;
    const blinkAmt = (ex.blink && !this._customSeq && this._tp >= 1 && bl >= 0 && bl < 1)
      ? Math.pow(Math.sin(bl * Math.PI), 0.82) : 0;

    // Continuous weightless hover & gentle breath when not locked to `fixed`
    const floatOn = !calm && !fixed && this._idleMotion !== 'off';
    const ph = this._ph;
    const floatX = floatOn ? (.020 * Math.sin(t * .92 + ph) + .009 * Math.sin(t * 2.05 + ph * 1.7)) : 0;
    const floatY = floatOn ? (-.026 * Math.sin(t * 1.18 + ph * .8) - .009 * Math.cos(t * 2.25 + ph)) : 0;
    const breath = floatOn ? .011 * Math.sin(t * 1.5 + ph) : 0;
    const s = (m.s ?? 1) + breath;
    const dy = (calm ? 0 : (m.dy || 0) + spinDy) + floatY;
    const dx = calm ? 0 : floatX;

    let energy = 0;
    for (let i = 0; i < 6; i++) energy += Math.abs(jx[i]) + Math.abs(this._jv[i]) * .02;
    const jiggle = energy > 2e-4 && !inSpin;
    const fx = this._tp < 1 ? EX[this._fromExpr] : null;
    const extras = this._extras && ((ex.extra && (EXTRA[ex.extra] || BACK[ex.extra])) || (fx && fx.extra));
    const stride = Math.max(LEVELS[Q.level].stride, this._cssW < 44 ? 2 : 1);

    const sig = [yaw, pitch, headYaw, headPitch, eyeRoll, bodyRoll, blinkAmt, s, dx, dy, W, this._colorVer, stride, this._shadow ? 1 : 0, this._btp];
    if (!dyn && !jiggle && !extras && this._sig && this._sigBody === body && sig.every((v, i) => Math.abs(v - this._sig[i]) < 1e-4)) return;
    this._sigBody = body;
    this._sig = sig;
    if (extras && ++this._inkAt % 120 === 0) this._colors();

    const M = mat3D(headYaw, headPitch, bodyRoll);
    const localFr = frame3D(yaw - headYaw, pitch - headPitch, eyeRoll);
    const k = W / 3.2;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.clearRect(0, 0, W, W);
    c.setTransform(k, 0, 0, k, W / 2, W / 2);
    c.globalAlpha = 1;

    const contour = buildBodyContour(body, s, dx, dy, M, jx, jiggle, stride);
    const R = { c, k, W, a: 1, dy, sh: contour.sh, bodyPts: contour.pts, ink: this._ink, e: this._since, s };
    const layer = (tbl, e, op) => {
      if (extras && e && e.extra && tbl[e.extra] && op > .01) {
        R.a = op; tbl[e.extra](R, t + this._ph, pal); c.globalAlpha = 1;
      }
    };
    layer(BACK, fx, 1 - p); layer(BACK, ex, p);

    if (this._shadow) {
      c.globalAlpha = .20 * clamp(1 + dy * 1.5, .25, 1.3);
      c.fillStyle = pal.color; c.beginPath();
      const shadowRx = .62 * (body.isCircle ? 1 : lerp(body.zHalf, body.rx, Math.abs(M.m22))) * (1 + dy * .85) * (1 + jx[0] * .5);
      c.ellipse(dx * .6, body.floorY + .16, shadowRx, .058, 0, 0, TAU);
      c.fill(); c.globalAlpha = 1;
    }

    // Draw True 3D perspective cushion silhouette & clip face strictly inside it
    c.save();
    tracePts(c, contour.pts);
    c.fillStyle = pal.color;
    c.fill();
    c.clip();

    const warp = { s, dx: contour.dx, sh: contour.sh };
    drawFaceCells(c, localFr, M, this._curFace, blinkAmt, pal, body, this._face, warp, jx, jiggle, stride);
    c.restore();

    if (extras) {
      c.save();
      c.translate(dx, dy);
      layer(EXTRA, fx, 1 - p); layer(EXTRA, ex, p);
      c.restore();
    }
    this._Fr = localFr;
  }
}

OrbAvatar.shapes = {
  EX_X, EX_Y, SW,
  pill, rrect, superE, ell, qb, polyline, stroke, heavyPlus, heart,
  makeCell, buildEye, pairEyes, seqFace, seqGaze, hop, parseSVGPath
};
window.OrbAvatar = OrbAvatar;
customElements.define('orb-avatar', OrbAvatar);
if (typeof module !== 'undefined' && module.exports) module.exports = OrbAvatar;
})();
