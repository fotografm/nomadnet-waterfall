#!/usr/bin/env python3
"""
NomadNet executable page: 868 MHz waterfall.

Renders the collector's tmpfs ring as a Micron waterfall, newest row at the
top, using OpenWebRX's Turbo palette via 24-bit `FT/`BT tags. Each character
row carries two time rows via the upper-half-block glyph, which both doubles
time resolution and fixes the 2:1 terminal cell aspect.

Renders every signal present, without preference. Raw dB by default: no floor
subtraction, no squelch, and the colour scale is taken from the data's own
range so the strongest emitter in view -- whatever it is -- sits at the top of
the palette and remains distinguishable from anything weaker.

Query vars:  win (seconds), w (columns), h (character rows), flo/fhi (kHz),
             mono (1 = no colour), range (dB span), levels, squelch (dB),
             floor (1 = subtract per-bin median; hides constant carriers)
"""
import os, sys, json, time

GAP     = "222"          # no-data cell
BLOCK   = "▀"          # upper half block
RAMP    = " .:-=+*#%@"
# ---------------------------------------------------------------- CONFIG --
# Everything site-specific lives here. Nothing below this block needs editing.
SHM     = "/dev/shm/waterfall"                 # collector ring (tmpfs)
NNSTORE = "/root/.nomadnetwork/storage"        # NomadNet storage dir
NODEHASH_F = "/opt/waterfall/nodehash.txt"     # 32-hex node hash, see tools/nodehash.py
TURBO_F = "/opt/waterfall/turbo.json"          # 256-entry Turbo palette

# Default frequency window, in Hz. This only selects what is DISPLAYED; the
# collector always stores the full captured span, so zooming costs nothing.
DEF_LO, DEF_HI = 869_250_000, 869_800_000

# Your LXMF address, shown as a "Message me on ..." link in the footer.
# Leave empty to omit the line entirely.
LXMF_ADDR = ""
# ------------------------------------------------------------ END CONFIG --


def envint(name, default, lo, hi):
    try:
        v = int(os.environ.get("var_" + name, default))
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, v))


def banner(sub, note=None):
    print("`c`B112`Ffd0`! 868 MHz WATERFALL ``")
    print("`c`F777" + sub + "``")
    for ln in (note or []):
        print("`c`Fbcd" + ln + "``")
    print("-")


def bail(msg, detail=""):
    banner("source: vm103 RTL-SDR")
    print("`c`Ff55`!" + msg + "``")
    if detail:
        print("")
        print("`c`F777" + detail + "``")
    print("")
    sys.exit(0)


def main():
    import numpy as np

    try:
        with open(SHM + "/status.json") as f:
            st = json.load(f)
    except Exception:
        bail("Collector not running",
             "No spectrum ring yet. Start waterfall-collector on ct119.")

    rows, bins = st.get("rows", 0), st.get("bins", 0)
    if not bins:
        bail("No spectrum data yet", "Waiting for the first frames from vm103.")

    if "f_lo" not in st or "f_hi" not in st:
        bail("Collector not connected to vm103",
             st.get("note", "")[:120] or "No frequency geometry in status.")
    s_lo, s_hi = st["f_lo"], st["f_hi"]          # full captured span

    win  = envint("win", 300, 10, int(rows * st["row_secs"]))
    W    = envint("w", 80, 20, 200)
    H    = envint("h", 32, 6, 160)
    mono = os.environ.get("var_mono", "0") == "1"
    halfcell = os.environ.get("var_cells", "full") == "half"
    # live  = wrapper page that embeds the waterfall as an auto-refreshing
    #         Micron partial (NomadNet's own browser only -- see notes §6)
    # part  = render ONLY the ruler + waterfall, for use as that partial
    live = os.environ.get("var_live", "0") == "1"
    part = os.environ.get("var_part", "0") == "1"
    PAGE = "/page/live.mu" if live else "/page/index.mu"
    refresh = envint("refresh", 10, 1, 3600)
    hires = os.environ.get("var_hires", "")          # "1" horizontal, "q" quadrant
    if hires == "0":
        hires = ""
    # dot-matrix look: one small mark per cell on black, no subdivision
    DOTS = {"sq": "\u25aa", "bullet": "\u2022", "mid": "\u00b7",
            "circle": "\u25cf", "lozenge": "\u25c6", "braille": "\u28ff"}
    dotname = os.environ.get("var_dot", "braille")
    dotch = DOTS.get(dotname, "")
    if not dotch:
        dotname = "none"
    # Turbo's low end is near-black purple: fine as a filled block, but a small
    # dot in it disappears against the background. Lift the palette with a
    # gamma so dots stay visible. Hue still carries the level either way.
    bright = envint("bright", 100, 50, 400)
    dofloor = os.environ.get("var_floor", "0") == "1"   # off: show everything
    squelch = float(envint("squelch", 0, 0, 40))
    rng_override = envint("range", 0, 0, 120)

    # Default view, clamped into whatever vm103 is actually capturing. This
    # selects what is on screen; it never decides what counts as a signal.
    d_lo = max(s_lo, DEF_LO); d_hi = min(s_hi, DEF_HI)
    if d_hi - d_lo < 50_000:
        d_lo, d_hi = s_lo, s_hi
    flo = envint("flo", int(d_lo // 1000), int(s_lo // 1000), int(s_hi // 1000)) * 1000
    fhi = envint("fhi", int(d_hi // 1000), int(s_lo // 1000), int(s_hi // 1000)) * 1000
    if fhi - flo < 20_000:
        flo, fhi = d_lo, d_hi
    b0 = int((flo - s_lo) / (s_hi - s_lo) * bins)
    b1 = max(b0 + 1, int((fhi - s_lo) / (s_hi - s_lo) * bins))

    cur = {}
    if win != 300:   cur["win"] = win
    if W != 80:      cur["w"] = W
    if H != 32:      cur["h"] = H
    if flo != d_lo:  cur["flo"] = flo // 1000
    if fhi != d_hi:  cur["fhi"] = fhi // 1000
    if halfcell:     cur["cells"] = "half"
    if hires:        cur["hires"] = hires
    if dotname != "braille": cur["dot"] = dotname
    if dofloor:      cur["floor"] = 1
    if squelch:      cur["squelch"] = int(squelch)
    if mono:         cur["mono"] = 1
    if rng_override: cur["range"] = rng_override
    if bright != 100: cur["bright"] = bright

    if not part:
        banner("%.3f - %.3f MHz   .   captured %.2f - %.2f MHz   .   vm103 RTL-SDR"
               % (flo / 1e6, fhi / 1e6, s_lo / 1e6, s_hi / 1e6),
               ["Try the different rendering modes.",
                "I like the Braille one with brightness 100 best."])
        if not st.get("connected", False):
            print("`c`Ff55Collector disconnected: %s``" % st.get("note", "")[:60])
            print("")

    if live:
        # One partial, refreshed in place by the browser. Fields carry the
        # current view so the embedded waterfall matches the wrapper's links.
        f = dict(cur)
        q = "|".join("%s=%s" % (k, f[k]) for k in sorted(f))
        print("`c`F777auto-refreshing every %d seconds``" % refresh)
        print("")
        # A client that implements Micron partials replaces the next line with
        # the waterfall and re-requests it on the interval. One that does not
        # prints the directive as text -- there is no way to hide it from only
        # those clients, so say what it is instead.
        print("`c`F888If the next line stays a placeholder or shows markup,``")
        print("`c`F888this client does not support Micron partials. Needs``")
        print("`c`F888the NomadNet browser or MeshChatX 4.9+.``")
        print("")
        # MeshChatX's PARTIAL_LINE_REGEX is
        #   /^`\{([a-f0-9]{32}):([^`}]*)(?:`(\d+)(?:`([^}]*))?)?\}$/
        # so it requires an ABSOLUTE url carrying this node's 32-hex
        # destination hash. NomadNet accepts both that and the relative ":"
        # form, so always emit the absolute one -- the relative form leaves
        # MeshChatX stuck on its loading placeholder for ever.
        try:
            with open(NODEHASH_F) as nf:
                nh = nf.read().strip()
        except Exception:
            nh = ""
        print("`{%s:/page/wf.mu`%d%s}" % (nh, refresh, ("`" + q) if q else ""))
        print("")
    else:
        ring  = np.memmap(SHM + "/ring.dat",  dtype=np.float32, mode="r", shape=(rows, bins))
        times = np.memmap(SHM + "/times.dat", dtype=np.float64, mode="r", shape=(rows,))

        order = (int(st["idx"]) - 1 - np.arange(rows)) % rows      # newest first
        t = np.asarray(times)[order]
        d = np.asarray(ring)[order]

        have = t > 0
        if not have.any():
            bail("No spectrum data yet", "Waiting for the first frames from vm103.")

        newest = t[have].max()
        sel = have & (t >= newest - win)
        d, t = d[sel], t[sel]
        n = len(t)

        if dofloor:
            allrows = np.asarray(ring)[have]
            if len(allrows) > 300:
                allrows = allrows[:: max(1, len(allrows) // 300)]
            with np.errstate(all="ignore"):
                floor = np.nan_to_num(np.nanmedian(allrows, axis=0), nan=0.0)
        else:
            floor = np.zeros(bins, dtype=np.float32)

        d, floor = d[:, b0:b1], floor[b0:b1]
        nb = b1 - b0

        # Sub-cell resolution. A character can carry one foreground and one
        # background colour, so hires packs a 2x2 pixel block into every cell via
        # quadrant glyphs: the page occupies the same W x H character area but
        # carries 4x the data points, at the cost of approximating each 2x2 group
        # to two colours.
        if mono:
            TH, GW = H, W
        elif hires == "q":
            TH, GW = H * 2, W * 2
        elif hires:
            # Horizontal subdivision only. Time edges then always land on a
            # character-row boundary, so solid blocks keep clean flat tops and
            # bottoms, and every cell can use the SAME glyph -- which is what
            # keeps row widths identical and the columns aligned.
            TH, GW = H, W * 2
        elif halfcell:
            TH, GW = H * 2, W
        else:
            TH, GW = H, W
        TH = min(TH, max(n, 1))
        if hires == "q":
            TH = max(2, TH - (TH % 2))

        # time buckets (peak hold) then frequency columns (peak hold)
        tedge = np.linspace(0, n, TH + 1).astype(int)
        cedge = np.linspace(0, nb, GW + 1).astype(int)
        grid = np.full((TH, GW), np.nan, dtype=np.float32)
        for g in range(TH):
            a, b = tedge[g], tedge[g + 1]
            if b <= a:
                a, b = min(a, n - 1), min(a, n - 1) + 1
            seg = d[a:b] - floor
            with np.errstate(all="ignore"):
                prof = np.nanmax(seg, axis=0)
            for c in range(GW):
                ca, cb = cedge[c], cedge[c + 1]
                if cb <= ca:
                    cb = ca + 1
                chunk = prof[ca:cb]
                if np.isnan(chunk).all():
                    continue
                grid[g, c] = np.nanmax(chunk)

        finite = grid[np.isfinite(grid)]
        if finite.size == 0:
            bail("No spectrum data yet", "Ring is present but empty.")

        # Scale taken from the data itself. The strongest emitter in view reaches
        # the top of the palette whatever it is, so nothing saturates into a tie.
        top = float(np.max(finite))
        if rng_override:
            lo_db, hi_db = top - rng_override, top
        else:
            lo_db = float(np.percentile(finite, 10)) - 2.0
            hi_db = top
            if hi_db - lo_db < 20.0:
                hi_db = lo_db + 20.0
        lo_db += squelch
        span = max(hi_db - lo_db, 1.0)

        lvl = (grid - lo_db) / span
        np.clip(lvl, 0.0, 1.0, out=lvl)

        units = "dB over per-bin median" if dofloor else "dBFS"

        # ---- frequency ruler -------------------------------------------------
        def col_of(f):
            return int(round((f - flo) / (fhi - flo) * (W - 1)))

        span_hz = fhi - flo
        step = 500_000
        for cand in (5_000, 10_000, 20_000, 25_000, 50_000,
                     100_000, 200_000, 250_000, 500_000, 1_000_000):
            if span_hz / cand <= 6:
                step = cand
                break
        ticks = [f for f in range(((flo // step) + 1) * step, fhi + 1, step)]
        tickline = [" "] * W
        lblline = [" "] * W
        for f in ticks:
            c = col_of(f)
            if 0 <= c < W:
                tickline[c] = "|"
                lab = ("%.3f" % (f / 1e6)).rstrip("0").rstrip(".")
                s = max(0, min(W - len(lab), c - len(lab) // 2))
                if all(lblline[s + k] == " " for k in range(len(lab))):
                    for k, ch in enumerate(lab):
                        lblline[s + k] = ch
        def cell_line(chars, fga, fgb):
            # same emission shape as a waterfall row: `B then `F then one glyph,
            # colours alternating so adjacent cells can never be merged into one
            # span. Keeps the ruler exactly W spans wide, matching the image.
            parts = []
            for i, ch in enumerate(chars):
                parts.append("`B000")
                parts.append("`F" + (fga if i % 2 == 0 else fgb))
                parts.append(ch)
            parts.append("``")
            return "".join(parts)

        print(cell_line(lblline, "888", "889"))
        print(cell_line(tickline, "0f0", "0f1"))

        # ---- waterfall -------------------------------------------------------
        if mono:
            for g in range(TH):
                row = []
                for c in range(W):
                    v = lvl[g, c]
                    row.append(" " if not np.isfinite(v)
                               else RAMP[min(len(RAMP) - 1, int(v * (len(RAMP) - 1) + 0.5))])
                print("".join(row))
        else:
            with open(TURBO_F) as f:
                turbo = json.load(f)
            # Quantising the palette collapses near-identical cells into longer
            # same-colour runs for the run-length emitter below. Turbo is smooth
            # enough that 64 steps is visually indistinguishable at this cell size.
            levels = envint("levels", 64, 8, 256)
            gam = 100.0 / bright

            def h3(v):
                ch = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                if gam != 1.0:
                    ch = tuple(int(255.0 * (c / 255.0) ** gam) for c in ch)
                return "%X%X%X" % (ch[0] >> 4, ch[1] >> 4, ch[2] >> 4)
            pal = [h3(turbo[int(i * 255 / (levels - 1))]) for i in range(levels)]

            def colour(v):
                if not np.isfinite(v):
                    return GAP
                return pal[min(levels - 1, max(0, int(v * (levels - 1) + 0.5)))]

            # Emit a tag for EVERY cell rather than only on colour change. Clients
            # that render each colour run as its own span pick up a sub-pixel
            # rounding error per span; run-length encoding gives each row a
            # different span count, so each row drifts by a different amount and
            # bursts stop lining up vertically. A fixed tag-per-cell makes the
            # span count identical on every row, so any drift is identical too and
            # the columns stay square. Costs bytes, buys alignment. rle=1 restores
            # the smaller run-length form.
            rle = os.environ.get("var_rle", "0") == "1"
            nomerge = os.environ.get("var_nomerge", "1") == "1"

            def nudge(h):
                # flip the low bit of the blue nibble: 1/16 of one channel, below
                # the eye's threshold at this cell size, but enough that the style
                # differs from its neighbour so the renderer cannot merge the two
                # into one run. Keeps the run count fixed at W on every row.
                return h[:2] + "%X" % (int(h[2], 16) ^ 1)

            # Quadrant glyphs indexed by a 4-bit mask, TL=8 TR=4 BL=2 BR=1.
            QUAD = (" \u2597\u2596\u2584\u259d\u2590\u259e\u259f"
                    "\u2598\u259a\u258c\u2599\u2580\u259c\u259b\u2588")

            if hires and hires != "q":
                # every cell is U+258C, left half = one sub-cell, right half the
                # next. One glyph everywhere => uniform row width.
                for r in range(TH):
                    parts = []
                    prev = None
                    for c in range(0, GW - (GW % 2), 2):
                        fg = colour(lvl[r, c])
                        bg = colour(lvl[r, c + 1])
                        if nomerge and (fg, bg) == prev:
                            fg = nudge(fg)
                        prev = (fg, bg)
                        parts.append("`B" + bg)
                        parts.append("`F" + fg)
                        parts.append("\u258c")
                    parts.append("``")
                    print("".join(parts))
            elif dotch:
                for r in range(TH):
                    parts = []
                    prev = None
                    for c in range(W):
                        fg = colour(lvl[r, c])
                        if nomerge and fg == prev:
                            fg = nudge(fg)
                        prev = fg
                        parts.append("`B000")
                        parts.append("`F" + fg)
                        parts.append(dotch)
                    parts.append("``")
                    print("".join(parts))
            elif hires == "q":
                for r in range(0, TH - (TH % 2), 2):
                    parts = []
                    prev = None
                    for c in range(0, GW - (GW % 2), 2):
                        q = (lvl[r, c], lvl[r, c + 1], lvl[r + 1, c], lvl[r + 1, c + 1])
                        fin = [v for v in q if np.isfinite(v)]
                        alt = "000" if (c // 2) % 2 == 0 else "111"
                        cols = [colour(v) for v in q]
                        if not fin:
                            fg, bg, ch = alt, GAP, " "
                        elif len(set(cols)) == 1:
                            # All four quantise to one colour, so no glyph is
                            # needed: paint the background and leave the (inkless)
                            # foreground free for the anti-merge alternation. Never
                            # use a full block over black here -- fonts rarely fill
                            # the cell and the black shows as comb teeth.
                            fg, bg, ch = alt, cols[0], " "
                        else:
                            lo_l, hi_l = min(fin), max(fin)
                            mid = (lo_l + hi_l) / 2.0
                            hi_v = [v for v in fin if v > mid] or [hi_l]
                            lo_v = [v for v in fin if v <= mid] or [lo_l]
                            fg = colour(sum(hi_v) / len(hi_v))
                            bg = colour(sum(lo_v) / len(lo_v))
                            bits = 0
                            for i, v in enumerate(q):
                                if np.isfinite(v) and v > mid:
                                    bits |= (8 >> i)
                            ch = QUAD[bits]
                            if nomerge and (fg, bg, ch) == prev:
                                fg = nudge(fg)
                        prev = (fg, bg, ch)
                        parts.append("`B" + bg)
                        parts.append("`F" + fg)
                        parts.append(ch)
                    parts.append("``")
                    print("".join(parts))
            elif halfcell:
                for r in range(0, TH - (TH % 2), 2):
                    parts = []
                    cfg = cbg = None
                    prev = None
                    for c in range(W):
                        fg = colour(lvl[r, c])
                        bg = colour(lvl[r + 1, c])
                        if nomerge and (fg, bg) == prev:
                            fg = nudge(fg)
                        prev = (fg, bg)
                        if fg != cfg or not rle:
                            parts.append("`F" + fg); cfg = fg
                        if bg != cbg or not rle:
                            parts.append("`B" + bg); cbg = bg
                        parts.append(BLOCK)
                    parts.append("``")
                    print("".join(parts))
            else:
                # one time row per character row, background colour only: needs no
                # glyph beyond a space, so it renders anywhere
                for r in range(TH):
                    parts = []
                    cbg = None
                    cfg = None
                    prev = None
                    for c in range(W):
                        bg = colour(lvl[r, c])
                        # a space has no ink, so the foreground is a free channel:
                        # alternate it to force a distinct style on every cell
                        fg = "000" if (c % 2 == 0) else "111"
                        if bg != cbg or not rle:
                            parts.append("`B" + bg); cbg = bg
                        if nomerge and fg != cfg:
                            parts.append("`F" + fg); cfg = fg
                        parts.append(" ")
                    parts.append("``")
                    print("".join(parts))

        # ---- footer ----------------------------------------------------------
        secs_per_row = (t.max() - t.min()) / max(TH - 1, 1) if n > 1 else st["row_secs"]
        age = time.time() - newest
        stale = "" if age < 15 else "   `Ff55STALE %d s" % age
        print("-")
        print("`F777window `Ffff%d s`F777   rows `Ffff%d`F777   %.1f s/row   "
              "%.2f kHz/col``" % (win, TH, secs_per_row, (fhi - flo) / 1000.0 / GW))
        print("`F777scale `Ffff%.0f .. %.0f %s`F777   peak hold   updated "
              "`Ffff%s UTC (Zulu)`F777%s``"
              % (lo_db, hi_db, units,
                 time.strftime("%H:%M:%S", time.gmtime(newest)), stale))
        print("")

    if part:
        sys.exit(0)

    # ---- footer links ----------------------------------------------------
    # Every link carries the current view forward, so changing width, height
    # or window keeps whatever rendering mode is selected instead of snapping
    # back to the default. Passing None for a key drops it.

    def L(label, **over):
        d = dict(cur)
        for k, v in over.items():
            if v is None:
                d.pop(k, None)
            else:
                d[k] = v
        q = "|".join("%s=%s" % (k, d[k]) for k in sorted(d))
        return "`[%s`:%s%s]" % (label, PAGE, ("`" + q) if q else "")

    # selecting one rendering mode clears the others
    def R(label, **over):
        base = dict(hires=None, dot="none", cells=None)
        base.update(over)
        return L(label, **base)

    print("")
    # Cross-link to the other wrapper, carrying the current view with it.
    # Given its own row because only one client can actually use it.
    _q = "|".join("%s=%s" % (k, cur[k]) for k in sorted(cur))
    _tail = ("`" + _q) if _q else ""
    if live:
        print("`F777Live:   `[static page`:/page/index.mu%s]``" % _tail)
        print("`F888        Auto-refresh needs the NomadNet browser or MeshChatX 4.9+.``")
    else:
        print("`F777Live:   `[live waterfall (auto-refresh)`:/page/live.mu%s]``" % _tail)
        print("`F888        Needs the NomadNet browser or MeshChatX 4.9+; "
              "plain MeshChat will not.``")
    print("")
    print("`F777Span:   " + "  ".join(L(t, win=v) for t, v in (
        ("1 min", 60), ("2 min", 120), ("5 min", 300), ("15 min", 900))) + "``")
    print("`F777Freq:   " + "  ".join([
        L("all captured", flo=int(s_lo // 1000), fhi=int(s_hi // 1000)),
        L("869.25-869.80", flo=869250, fhi=869800),
        L("869.40-869.70", flo=869400, fhi=869700)]) + "``")
    print("`F777Width:  " + "  ".join(L(str(v), w=v) for v in (72, 76, 80, 96)) + "``")
    print("`F777Height: " + "  ".join(L(str(v), h=v) for v in (32, 48, 64, 96)) + "``")
    print("`F777Render: " + "  ".join([
        R("blocks"), R("hi-res", hires=1), R("quad", hires="q"),
        R("half", cells="half")]) + "``")
    print("`F777Dots:   " + "  ".join(R(n, dot=k) for n, k in (
        ("square", "sq"), ("bullet", "bullet"), ("middot", "mid"),
        ("circle", "circle"), ("braille", "braille"))) + "``")
    print("`F777Bright: " + "  ".join(L(str(v), bright=v) for v in
                                      (100, 150, 190, 240, 300)) + "``")
    print("`F777View:   " + "  ".join([
        L("refresh"),
        L("colour", mono=None) if mono else L("mono", mono=1),
        L("raw dB", floor=None) if dofloor else L("subtract floor", floor=1)]) + "``")

    # ---- visit counter ---------------------------------------------------
    # This page only. Wrapped so a counter fault can never take the page down.
    # State lives outside pages/ so NomadNet cannot serve it; delete the file
    # to reset, or edit "total" to seed it.
    page_n = since = None
    try:
        import fcntl
        cdir = NNSTORE + "/pagecounts"
        os.makedirs(cdir, exist_ok=True)
        with open(cdir + "/index.count", "a+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0)
            try:
                cs = json.loads(f.read())
            except Exception:
                cs = {}
            cs["total"] = int(cs.get("total", 0)) + 1
            cs.setdefault("since", time.time())
            f.seek(0); f.truncate(); f.write(json.dumps(cs))
            fcntl.flock(f, fcntl.LOCK_UN)
        page_n = cs["total"]
        since = time.strftime("%Y-%m-%d", time.gmtime(cs["since"]))
    except Exception:
        pass

    print("")
    if page_n is not None:
        print("`F777Page views: `Ffff%d`F777%s``"
              % (page_n, ("   since " + since) if since else ""))
    # lxmf@<32 hex> is a real link target: Browser.expand_shorthands maps the
    # "lxmf" prefix to "lxmf.delivery", which handle_link routes to
    # handle_lxmf_link and opens a conversation with that peer.
    if LXMF_ADDR:
        print("`F777Message me on `[%s`lxmf@%s]``" % (LXMF_ADDR, LXMF_ADDR))


try:
    main()
except SystemExit:
    raise
except Exception as e:
    print("`c`Ff55`!Render error``")
    print("")
    print("`F777" + repr(e)[:300] + "``")
