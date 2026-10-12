// SPDX-License-Identifier: BSL-1.0
// Waveform view shared by the EasyCDR trace viewer (index.html) and the
// SLogic16U3 logic analyzer UI (eda/slogic16u3_la/host/web/la.html).
//
// The view draws "segments": {xa, xb, or, and, nd} over x (ns or samples),
// or / and = the OR and AND of every value inside the segment (BigInt bit
// masks over the whole data word; or == and: one value, else the bits that
// differ changed inside it - a zoomed-out summary), nd = bits with no data.
// A source with exact records gives segments with or == and; the LA server
// gives one per pixel when zoomed out and the samples themselves when in.
//
// Also here: the signal map (same syntax and CRC-32 canonical form as
// eda/easycdr_trace/host/tracemap.py) and the condition expressions.
'use strict';
const Wave = (() => {
  // ---------------------------------------------------------------- signal map
  const CRC_TBL = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
  function crc32(str) { let c = 0xffffffff; for (const b of new TextEncoder().encode(str)) c = CRC_TBL[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }

  // name[:width[:radix]] entries (comma / line separated, LSB first), derived: name = expr
  function parseMap(text) {
    const sigs = [], derived = []; let lsb = 0;
    for (const line of text.split('\n')) {
      const body = line.split('#')[0];
      const dm = body.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)([\s\S]*)$/);   // derived: name = expr (excluded from hash)
      if (dm) { derived.push({ name: dm[1], expr: dm[2].trim(), width: 1, radix: 'bin', derived: true }); continue; }
      for (const raw of body.split(',')) {
        const s = raw.trim(); if (!s) continue;
        const m = s.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(\d+)\s*(?::\s*(.+))?)?$/);
        if (!m) throw new Error('bad entry: ' + s);
        const name = m[1], width = m[2] ? +m[2] : 1; let radix = (m[3] || 'hex').trim(); let names = null;
        const en = radix.match(/^enum\s*\((.*)\)$/i);
        if (en) { names = en[1].split(/[,\s]+/).filter(Boolean); radix = 'enum'; } else radix = radix.toLowerCase();
        if (!(width >= 1 && width <= 64)) throw new Error('bad width for ' + name);
        if (!['hex', 'dec', 'bin', 'enum'].includes(radix)) throw new Error('bad radix for ' + name);
        sigs.push({ name, width, radix, names, lsb }); lsb += width;
      }
    }
    const canon = sigs.map(s => `${s.name}:${s.width}`).join(',');
    // derived expressions: identifiers -> values, &,|,^,~,!,==,!=,<,>,(),numbers
    const byName = new Map(sigs.map(s => [s.name, s]));
    for (const d of derived) {
      const js = d.expr.replace(/0x[0-9a-fA-F]+|\d+|[A-Za-z_][A-Za-z0-9_]*|&&|\|\||[&|^~!=<>()]|==|!=/g, tok => {
        if (/^0x/.test(tok) || /^\d+$/.test(tok)) return `${tok}n`;
        if (/^[A-Za-z_]/.test(tok)) { if (!byName.has(tok)) throw new Error(`derived ${d.name}: unknown signal ${tok}`); return `v.${tok}`; }
        return tok;
      });
      if (/[^0-9a-zA-Z_.\s&|^~!=<>()n]/.test(js)) throw new Error(`derived ${d.name}: unsupported characters`);
      try { d.fn = new Function('v', `return (${js}) ? 1n : 0n;`); } catch (e) { throw new Error(`derived ${d.name}: ${e.message}`); }
    }
    const map = { sigs, derived, width: lsb, hash: crc32(canon), canon };
    for (const d of derived) d.map = map;
    return map;
  }
  // one row per bit when there is no map
  function bitRows(width, prefix = '') { return Array.from({ length: width }, (_, b) => ({ name: `${prefix}${b}`, lsb: b, width: 1, radix: 'bin' })); }
  function sigValues(map, data) { const v = {}; for (const s of map.sigs) v[s.name] = (data >> BigInt(s.lsb)) & ((1n << BigInt(s.width)) - 1n); return v; }
  function sigValue(s, data) { return s.derived ? s.fn(sigValues(s.map, data)) : (data >> BigInt(s.lsb)) & ((1n << BigInt(s.width)) - 1n); }
  function fieldMask(s) { return s.derived ? (s.map.width ? (1n << BigInt(s.map.width)) - 1n : 0n) : ((1n << BigInt(s.width)) - 1n) << BigInt(s.lsb); }
  function fmtSig(s, v) {
    if (s.radix === 'enum') return (s.names && s.names[Number(v)] !== undefined) ? s.names[Number(v)] : String(v);
    if (s.radix === 'dec') return v.toString(10);
    if (s.radix === 'bin') return v.toString(2).padStart(s.width, '0');
    return '0x' + v.toString(16).padStart(Math.ceil(s.width / 4), '0');
  }

  // ---------------------------------------------------------------- conditions
  // terms joined by &&: name == value | name (!= 0) | !name | rise(name) | fall(name) | edge(name)
  // -> BigInt masks over the map's bits: mask/val (levels), rise, fall, edge (1-bit signals)
  function parseCond(map, expr) {
    let mask = 0n, val = 0n, rise = 0n, fall = 0n, edge = 0n;
    for (const raw of expr.split('&&')) {
      const t = raw.trim(); if (!t) continue;
      const sig = n => { const s = map.sigs.find(x => x.name === n); if (!s) throw new Error('unknown signal: ' + n); return s; };
      const em = t.match(/^(rise|fall|edge)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)$/);
      if (em) {
        const s = sig(em[2]); if (s.width !== 1) throw new Error(`${em[1]}(${s.name}): 1-bit signals only`);
        const b = 1n << BigInt(s.lsb);
        if (em[1] === 'rise') rise |= b; else if (em[1] === 'fall') fall |= b; else edge |= b;
        continue;
      }
      const m = t.match(/^(!?)\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:==\s*(.+))?$/);
      if (!m) throw new Error('bad term: ' + t);
      const s = sig(m[2]);
      let v;
      if (m[3] !== undefined) { const lit = m[3].trim(); const ei = s.names ? s.names.indexOf(lit) : -1; v = ei >= 0 ? BigInt(ei) : BigInt(lit); }
      else v = m[1] ? 0n : 1n;
      const w = (1n << BigInt(s.width)) - 1n;
      if (v > w) throw new Error(`${s.name}: value too wide`);
      mask |= w << BigInt(s.lsb); val |= (v & w) << BigInt(s.lsb);
    }
    return { mask, val, rise, fall, edge };
  }
  function exprToMaskVal(map, expr) {
    const c = parseCond(map, expr);
    if (c.rise | c.fall | c.edge) throw new Error('edges (rise/fall/edge) are not supported here');
    return { mask: c.mask, val: c.val };
  }
  // condition -> one character per bit (X 0 1 R F E), bit 0 first
  function condCodes(c, width) {
    let s = '';
    for (let b = 0n; b < BigInt(width); b++) {
      const m = 1n << b;
      s += (c.rise & m) ? 'R' : (c.fall & m) ? 'F' : (c.edge & m) ? 'E' : (c.mask & m) ? ((c.val & m) ? '1' : '0') : 'X';
    }
    return s;
  }

  // ---------------------------------------------------------------- formatting
  function niceStep(v) { const e = Math.pow(10, Math.floor(Math.log10(v))); const m = v / e; return (m < 2 ? 1 : m < 5 ? 2 : 5) * e; }
  // x (ns, or samples) as text; res: the resolution worth showing (decimals)
  function fmtX(x, unit, res) {
    if (unit !== 'ns') return Math.round(x).toString();
    const a = Math.max(Math.abs(x), Math.abs(res || 0));
    const [div, u] = a >= 1e9 ? [1e9, 's'] : a >= 1e6 ? [1e6, 'ms'] : a >= 1e3 ? [1e3, 'µs'] : [1, 'ns'];
    const r = Math.abs(res || x) / div;
    const dec = r > 0 ? Math.min(6, Math.max(0, -Math.floor(Math.log10(r) + 1e-9))) : 0;
    return (x / div).toFixed(dec) + ' ' + u;
  }
  function fmtFreq(hz) { const a = Math.abs(hz); return a >= 1e9 ? (hz / 1e9).toPrecision(4) + ' GHz' : a >= 1e6 ? (hz / 1e6).toPrecision(4) + ' MHz' : a >= 1e3 ? (hz / 1e3).toPrecision(4) + ' kHz' : hz.toPrecision(4) + ' Hz'; }

  // ---------------------------------------------------------------- view
  class View {
    // opts: {unit: 'ns' | 'sample', onChange(x0, x1, npx): the visible range changed, onCursor()}
    constructor(canvas, opts = {}) {
      this.cv = canvas; this.unit = opts.unit || 'ns'; this.onChange = opts.onChange || null; this.onCursor = opts.onCursor || null;
      this.rows = []; this.segs = []; this.bounds = null; this.markers = []; this.cursors = { a: null, b: null };
      this.t0 = 0; this.span = 1; this.labelW = 48; this.highlight = 0n;
      this._drag = null;
      canvas.addEventListener('wheel', e => {
        e.preventDefault();
        const r = canvas.getBoundingClientRect(), px = e.clientX - r.left;
        if (px < this.labelW) return;
        const t = this.xToT(px), f = Math.pow(1.0015, e.deltaY);
        this.span = Math.max(this.minSpan(), this.span * f); this.t0 = t - (px - this.labelW) / this.plotW() * this.span;
        this.changed();
      }, { passive: false });
      canvas.addEventListener('pointerdown', e => {
        canvas.setPointerCapture(e.pointerId);
        this._drag = { x: e.clientX, t0: this.t0, moved: false, shift: e.shiftKey };
      });
      canvas.addEventListener('pointermove', e => {
        const d = this._drag; if (!d) return;
        const dx = e.clientX - d.x; if (Math.abs(dx) > 3) d.moved = true;
        if (d.moved) { this.t0 = d.t0 - dx / this.plotW() * this.span; this.changed(); }
      });
      canvas.addEventListener('pointerup', e => {
        const d = this._drag; this._drag = null; if (!d || d.moved) return;
        const r = canvas.getBoundingClientRect(), px = e.clientX - r.left; if (px < this.labelW) return;
        const t = this.snap(this.xToT(px));
        if (d.shift) this.cursors.b = t; else this.cursors.a = t;
        this.draw(); if (this.onCursor) this.onCursor();
      });
      canvas.addEventListener('dblclick', () => { this.cursors = { a: null, b: null }; this.draw(); if (this.onCursor) this.onCursor(); });
      new ResizeObserver(() => this.changed()).observe(canvas);
    }
    plotW() { return Math.max(1, this.cv.clientWidth - this.labelW); }
    minSpan() { return this.unit === 'ns' ? 1 : 4; }
    xToT(px) { return this.t0 + (px - this.labelW) / this.plotW() * this.span; }
    tToX(t) { return this.labelW + (t - this.t0) / this.span * this.plotW(); }
    // a cursor goes to the nearest change when one is within 4 px
    snap(t) {
      const tol = this.span / this.plotW() * 4; let best = t, bd = tol;
      for (const s of this.segs) { const d = Math.abs(s.xa - t); if (d < bd) { bd = d; best = s.xa; } }
      return best;
    }
    setRows(rows) { this.rows = rows; this.draw(); }
    setSegments(segs) { this.segs = segs; this.draw(); }
    fit(x0, x1) { if (!(x1 > x0)) { x0 = this.bounds ? this.bounds.x0 : 0; x1 = this.bounds ? this.bounds.x1 : 1; } const m = (x1 - x0) * 0.01; this.t0 = x0 - m; this.span = Math.max(this.minSpan(), x1 - x0 + 2 * m); this.changed(); }
    center(t, span) { if (span) this.span = Math.max(this.minSpan(), span); this.t0 = t - this.span / 2; this.changed(); }
    changed() { this.draw(); if (this.onChange) this.onChange(this.t0, this.t0 + this.span, Math.round(this.plotW())); }

    draw() {
      const cv = this.cv, dpr = devicePixelRatio || 1;
      const W = cv.clientWidth, H = cv.clientHeight; cv.width = W * dpr; cv.height = H * dpr;
      const g = cv.getContext('2d'); g.scale(dpr, dpr); g.clearRect(0, 0, W, H);
      const css = getComputedStyle(cv), root = getComputedStyle(document.documentElement);
      const fg = css.color, acc = root.getPropertyValue('--acc') || '#2a6fdb', trigCol = root.getPropertyValue('--trig') || '#d33';
      const curCol = root.getPropertyValue('--cur') || '#c80';
      g.font = '11px monospace';
      const rows = this.rows, nr = Math.max(1, rows.length);
      this.labelW = Math.max(48, 8 + Math.max(0, ...rows.map(r => g.measureText(r.name).width)));
      const rowH = Math.min(24, (H - 22) / nr), x = t => this.tToX(t), labelW = this.labelW;
      // time axis
      const step = niceStep(this.span / 8);
      g.fillStyle = fg; g.strokeStyle = fg; g.lineWidth = 1; g.globalAlpha = .25;
      for (let t = Math.ceil(this.t0 / step) * step; t < this.t0 + this.span; t += step) {
        const px = x(t); g.beginPath(); g.moveTo(px, 0); g.lineTo(px, H - 14); g.stroke();
      }
      g.globalAlpha = 1;
      for (let t = Math.ceil(this.t0 / step) * step; t < this.t0 + this.span; t += step) g.fillText(fmtX(t, this.unit, step), x(t) + 2, H - 3);
      // outside the capture: shaded
      if (this.bounds) {
        g.globalAlpha = .08; g.fillStyle = fg;
        const xs = x(this.bounds.x0), xe = x(this.bounds.x1);
        if (xs > labelW) g.fillRect(labelW, 0, Math.min(xs, W) - labelW, H - 14);
        if (xe < W) g.fillRect(Math.max(labelW, xe), 0, W - Math.max(labelW, xe), H - 14);
        g.globalAlpha = 1;
      }
      // visible segments (binary search for the first)
      const segs = this.segs, tEnd = this.t0 + this.span;
      let lo = 0, hi = segs.length; while (lo < hi) { const m = (lo + hi) >> 1; if (segs[m].xb < this.t0) lo = m + 1; else hi = m; }
      for (let r = 0; r < rows.length; r++) {
        const s = rows[r], y0 = 2 + r * rowH, yH = y0 + rowH * .82, yL = y0 + rowH * .18, yM = (yH + yL) / 2;
        const fm = fieldMask(s), inHl = (this.highlight & fm) !== 0n && !s.derived;
        g.fillStyle = fg; g.fillText(s.name, 4, y0 + rowH * .68);
        g.save(); g.beginPath(); g.rect(labelW, 0, W - labelW, H); g.clip();
        g.strokeStyle = inHl ? trigCol : acc; g.fillStyle = g.strokeStyle;
        // runs of segments with the same state for this row: {xa, xb, v (BigInt) | null: changes inside}
        const runs = [];
        for (let n = lo; n < segs.length; n++) {
          const sg = segs[n]; if (sg.xa > tEnd) break;
          if (sg.nd && (sg.nd & fm)) { runs.push({ xa: sg.xa, xb: sg.xb, nd: true }); continue; }
          let v = null;
          if (s.derived) { if (sg.or === sg.and) v = sigValue(s, sg.and); }
          else if (((sg.or ^ sg.and) & fm) === 0n) v = sigValue(s, sg.and);
          const p = runs[runs.length - 1];
          if (p && !p.nd && p.v === v && sg.xa - p.xb < 1e-9 * Math.max(1, Math.abs(sg.xa))) { p.xb = sg.xb; continue; }
          runs.push({ xa: sg.xa, xb: sg.xb, v });
        }
        if (s.width === 1) {
          // a level line; a run with changes inside is a filled band
          let prevLvl = null, prevEnd = null;
          for (const u of runs) {
            const xa = x(u.xa), xb = x(u.xb);
            if (u.nd) { prevLvl = null; continue; }
            if (u.v === null) { g.globalAlpha = .55; g.fillRect(xa, yL, Math.max(1, xb - xa), yH - yL); g.globalAlpha = 1; prevLvl = null; prevEnd = xb; continue; }
            const y = u.v ? yL : yH;
            g.beginPath();
            if (prevLvl !== null && Math.abs(prevEnd - xa) < 1) { g.moveTo(xa, prevLvl ? yL : yH); g.lineTo(xa, y); } else g.moveTo(xa, y);
            g.lineTo(xb, y); g.stroke();
            prevLvl = u.v; prevEnd = xb;
          }
        } else {
          for (const u of runs) {
            if (u.nd) continue;
            const xa = x(u.xa), xb = x(u.xb), w = xb - xa;
            if (w <= 0) continue;
            if (u.v === null) { g.globalAlpha = .35; g.fillRect(xa, yL, Math.max(1, w), yH - yL); g.globalAlpha = 1; continue; }
            const k = Math.min(3, w / 2);
            g.beginPath(); g.moveTo(xa, yM); g.lineTo(xa + k, yL); g.lineTo(xb - k, yL); g.lineTo(xb, yM); g.lineTo(xb - k, yH); g.lineTo(xa + k, yH); g.closePath(); g.stroke();
            const txt = fmtSig(s, u.v), tw = g.measureText(txt).width, tx = Math.max(xa, labelW) + 4;
            if (tx + tw + 2 < xb) { g.fillStyle = fg; g.fillText(txt, tx, y0 + rowH * .68); g.fillStyle = g.strokeStyle; }
          }
        }
        g.restore();
      }
      // markers (trigger, capture ends) and cursors
      g.save(); g.beginPath(); g.rect(labelW, 0, W - labelW, H); g.clip();
      for (const m of this.markers) {
        const px = x(m.x); if (px < labelW || px > W) continue;
        g.strokeStyle = m.color === 'trig' ? trigCol : fg; g.fillStyle = g.strokeStyle; g.setLineDash(m.dash || [4, 3]);
        g.beginPath(); g.moveTo(px, 0); g.lineTo(px, H - 14); g.stroke(); g.setLineDash([]);
        if (m.label) g.fillText(m.label, px + 3, 10);
      }
      for (const [k, t] of Object.entries(this.cursors)) {
        if (t === null) continue; const px = x(t); if (px < labelW || px > W) continue;
        g.strokeStyle = curCol; g.fillStyle = curCol; g.beginPath(); g.moveTo(px, 0); g.lineTo(px, H - 14); g.stroke();
        g.fillText(k.toUpperCase(), px + 3, H - 16);
      }
      g.restore();
    }
    cursorText() {
      const { a, b } = this.cursors, f = t => fmtX(t, this.unit, this.span / 1000);
      if (a === null && b === null) return 'click: cursor A, shift+click: cursor B, double-click: clear';
      let s = (a !== null ? `A ${f(a)}` : '') + (b !== null ? `  B ${f(b)}` : '');
      if (a !== null && b !== null) {
        const d = b - a; s += `  Δ ${fmtX(d, this.unit, Math.abs(d) / 1000 || 1)}`;
        if (this.unit === 'ns' && d) s += ` (${fmtFreq(1e9 / Math.abs(d))})`;
      }
      return s;
    }
  }

  return { crc32, parseMap, bitRows, sigValues, sigValue, fieldMask, fmtSig, parseCond, exprToMaskVal, condCodes, niceStep, fmtX, fmtFreq, View };
})();
