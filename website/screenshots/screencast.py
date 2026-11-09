#!/usr/bin/env python3
"""Renders the feature screencast used on the docs home page, the README and social posts.

Usage: python3 website/screenshots/screencast.py [--ms target/release/ms] [-o out.gif] [--mp4 out.mp4]

Every command runs for real with the given `ms`, so the output shown is what the compiler prints.
Needs Python 3 with Pillow and the DejaVu Sans Mono font (and ffmpeg for --mp4); none are project
dependencies (see README.md). Scenes are listed in SCENES below; sources live in screencast/.
"""
import argparse, os, re, shutil, subprocess, sys, tempfile, textwrap
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "screencast")

# title: "*word*" is highlighted. steps: (command, keep(lines) -> lines shown); hold: extra ms on the last frame.
def first(n): return lambda ls: ls[:n]
def last(n): return lambda ls: ls[-n:]
def clock(ls): return [l for l in ls if l.startswith(("real", "user"))]
def bench_line(ls): return [l[len("BENCH "):].split(" (")[0] for l in ls if l.startswith("BENCH")]
SCENES = [
    dict(title="*Use-after-move?* Compile error.",
         sub="One owner per value. No GC, no refcounts, no surprises.",
         src="own.ms", steps=[("ms run own.ms", first(1))], cut=";"),
    dict(title="*No GC pauses.* C-class speed.",
         sub="Run time vs C with bounds checks, six kernels (bench/perf, 2026-11-09).",
         chart=True),
    dict(title="*All cores.* Regular functions.",
         sub="No async, no await, no function coloring.",
         phases=[
             dict(sub="One core: four jobs, one after another. User time equals real time.", src="seq.ms", hold=1800,
                  steps=[("ms build seq.ms -o seq && time ./seq", clock)]),
             dict(sub="Wrap each call in promise(fn: ...). Same fib, real time drops.", src="par.ms", hold=4600,
                  steps=[("ms build par.ms -o par && time ./par", clock)]),
         ]),
    dict(title="*Declare* effects. *Compiler checks* them.",
         sub="Mark db.write once; ms lint flags every caller that did not allow it.",
         src="effects.ms", hold=3200,
         steps=[("ms lint effects.ms", first(1))], cut=";"),
    dict(title="Compiler errors that *name the fix*.",
         sub="Cause and remedy in every diagnostic. --json for agents.",
         src="fixme.ms", steps=[("ms check fixme.ms", first(1))]),
    dict(title="A *complete toolchain*, in the box.",
         sub="test, fuzz, bench, profile: robust, performant programs, nothing to install.",
         src="tb.ms",
         steps=[("ms test tb.ms && ms bench tb.ms",
                 lambda ls: [l for l in ls if l.startswith("1 tests")] + bench_line(ls))], cut=" ("),
    dict(title="Including a *native profiler*.",
         sub="ms profile: source attribution, pprof, folded stacks. Nothing to install.",
         src="prof.ms", steps=[("ms profile prof.ms", lambda ls: ls[2:4])]),
    dict(title="*Token-lean* syntax, *benchmark-driven*.",
         sub="Fewer tokens to write and read, and we measure it.",
         points=["Compact syntax: less to generate, less to read.",
                 "Agents build real programs, scored on hidden tests.",
                 "Pass rate, tokens, turns and cost guide every change."]),
    dict(title="Can't read all that agent code? *Map it.*",
         sub="Call graph here; --format html writes an offline interactive code map.",
         src=None, steps=[("ms diagram par.ms --format ascii", first(6))]),
]
# Time relative to C compiled with bounds checks (1.0 = same), from bench/perf/results-2026-11-09.md: ms us / c-bounds us per kernel.
KERNELS = [("sieve", 28410 / 28204), ("nbody", 9024 / 8942), ("life", 4958 / 37967), ("matmul", 9098 / 10188),
           ("trees", 25892 / 25855), ("collatz", 244873 / 286587)]
URL = "manuscript-lang.github.io/manuscript"

W, H = 1280, 720
# the website's orange dark theme (website/assets/_custom.scss)
C = dict(top=(27, 18, 14), bot=(27, 18, 14), card=(36, 24, 16), bar=(71, 39, 25), edge=(120, 74, 46),
         fg=(255, 242, 230), dim=(192, 170, 153), acc=(255, 135, 62), acc2=(255, 171, 114), ok=(255, 200, 120),
         err=(255, 105, 105), kw=(255, 171, 114), st=(255, 135, 62), nu=(255, 214, 120), co=(150, 125, 105))
KEYWORDS = set("fn let var if else for in return try import from export type impl while match and or not true false none ok error test bench".split())
D = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono"
CODE, HEAD, SUB, SMALL = (ImageFont.truetype(D + ".ttf", 27), ImageFont.truetype(D + "-Bold.ttf", 47),
                          ImageFont.truetype(D + ".ttf", 22), ImageFont.truetype(D + ".ttf", 17))
CODE_S = ImageFont.truetype(D + ".ttf", 22)
CODE_XS = ImageFont.truetype(D + ".ttf", 20)
CODE_M = ImageFont.truetype(D + ".ttf", 24)
BIG = ImageFont.truetype(D + "-Bold.ttf", 104)
CW, LH, CARD = CODE.getlength("M"), 37, (60, 196, 1220, 650)
CW_S = CODE_S.getlength("M")
COLS = int((CARD[2] - CARD[0] - 64) / CW)
_bg = None

def background():
    global _bg
    if _bg is None:
        _bg = Image.new("RGB", (W, H))
        d = ImageDraw.Draw(_bg)
        for y in range(H):
            k = y / H
            d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * k) for a, b in zip(C["top"], C["bot"])))
    return _bg.copy()

def rich(d, x, y, text, font, color, accent):
    """Draw text where *marked* spans use the accent colour."""
    for i, part in enumerate(text.split("*")):
        if part:
            d.text((x, y), part, font=font, fill=accent if i % 2 else color)
            x += font.getlength(part)

def tokens(line):
    if line.lstrip().startswith("//"):
        return [(line, C["co"])]
    out = []
    for m in re.finditer(r'"(?:[^"\\]|\\.)*"|\w+|\s+|.', line):
        s = m.group(0)
        c = C["fg"]
        if s.startswith('"'): c = C["st"]
        elif s in KEYWORDS: c = C["kw"]
        elif s.isdigit(): c = C["nu"]
        out.append((s, c))
    return out

def chrome(d, n, total):
    d.rectangle([60, H - 36, 74, H - 22], fill=C["acc"])
    d.text((88, H - 40), "manuscript", font=SUB, fill=C["fg"])
    gap = 22
    x0 = W - 60 - gap * (total - 1)
    for i in range(total):
        r = 6 if i == n else 4
        d.ellipse([x0 + i * gap - r, H - 29 - r, x0 + i * gap + r, H - 29 + r], fill=C["acc"] if i == n else C["edge"])

def header(d, title, sub):
    rich(d, 60, 56, title, HEAD, C["fg"], C["acc"])
    d.text((60, 124), sub, font=SUB, fill=C["dim"])

def terminal(d):
    d.rounded_rectangle(CARD, 18, fill=C["card"], outline=C["edge"], width=2)
    d.rounded_rectangle([CARD[0], CARD[1], CARD[2], CARD[1] + 40], 18, fill=C["bar"])
    d.rectangle([CARD[0] + 2, CARD[1] + 22, CARD[2] - 2, CARD[1] + 40], fill=C["bar"])
    for i, c in enumerate([(237, 106, 94), (245, 191, 79), (97, 197, 84)]):
        d.ellipse([CARD[0] + 20 + i * 24, CARD[1] + 13, CARD[0] + 34 + i * 24, CARD[1] + 27], fill=c)

FONTS = [(CODE, CW, LH), (CODE_M, CODE_M.getlength("M"), 33), (CODE_S, CW_S, 31), (CODE_XS, CODE_XS.getlength("M"), 28)]

def fit(code, nrows):
    """Largest code font whose rows (code, gap, commands, output) fit in the terminal."""
    room = CARD[3] - CARD[1] - 62 - 34
    for f in FONTS:
        if (len(code) + (0.35 if code else 0) + nrows) * f[2] <= room:
            return f
    return FONTS[-1]

def scene_frame(sc, n, total, code, shown, rows, cursor):
    """rows: list of (kind, text) shown after the code: 'cmd', 'out', 'err'."""
    im = background()
    d = ImageDraw.Draw(im)
    header(d, sc["title"], sc.get("_sub", sc["sub"]))
    terminal(d)
    fnt, cw, lh = sc["_font"]
    x0, y = CARD[0] + 32, CARD[1] + 62
    visible = shown if isinstance(shown, (set, frozenset)) else set(range(shown))
    for i, line in enumerate(code):
        if i in visible:
            x = x0
            for s_, c in tokens(line):
                d.text((x, y), s_, font=fnt, fill=c)
                x += cw * len(s_)
        y += lh
    if code: y += int(lh * 0.35)
    cur = None
    if cursor and visible and not rows and code:
        last = max(visible)
        cur = (x0 + len(code[last]) * cw, CARD[1] + 62 + last * lh)
    for kind, text in rows:
        if kind == "cmd":
            d.text((x0, y), "$", font=fnt, fill=C["ok"])
            d.text((x0 + cw * 2, y), text, font=fnt, fill=C["fg"])
            cur = (x0 + cw * (2 + len(text)), y)
        else:
            d.text((x0, y), text, font=fnt, fill=C["err"] if kind == "err" else C["fg"])
            cur = None
        y += lh
    if cursor and cur:
        d.rectangle([cur[0] + 3, cur[1] + 3, cur[0] + cw * 0.55 + 3, cur[1] + lh - 8], fill=C["acc"])
    chrome(d, n, total)
    return im

def chart_frame(sc, n, total, bars):
    im = background()
    d = ImageDraw.Draw(im)
    header(d, sc["title"], sc["sub"])
    terminal(d)
    x0, y, scale = CARD[0] + 190, CARD[1] + 70, 480
    d.line([(x0 + scale, CARD[1] + 60), (x0 + scale, CARD[3] - 50)], fill=C["edge"], width=2)
    d.text((x0 + scale, CARD[3] - 34), "C + bounds checks = 1.0", font=SMALL, fill=C["dim"], anchor="mm")
    d.text((x0, CARD[3] - 34), "faster", font=SMALL, fill=C["dim"], anchor="lm")
    d.text((x0 + scale * 1.8, CARD[3] - 34), "slower", font=SMALL, fill=C["dim"], anchor="rm")
    for i, (name, ratio) in enumerate(KERNELS):
        d.text((CARD[0] + 32, y + 6), name, font=CODE_S, fill=C["fg"])
        if i < bars:
            w = max(4, scale * ratio)
            d.rounded_rectangle([x0, y, x0 + w, y + 30], 6, fill=C["acc"] if ratio <= 1.1 else C["acc2"])
            d.text((x0 + w + 12, y + 6), f"{ratio:.2f}x", font=CODE_S, fill=C["fg"])
        y += 46
    chrome(d, n, total)
    return im

def points_frame(sc, n, total, shown):
    im = background()
    d = ImageDraw.Draw(im)
    header(d, sc["title"], sc["sub"])
    terminal(d)
    y = CARD[1] + 80
    for i, text in enumerate(sc["points"][:shown]):
        d.ellipse([CARD[0] + 40, y + 9, CARD[0] + 58, y + 27], fill=C["acc"])
        d.text((CARD[0] + 84, y), text, font=CODE_M, fill=C["fg"])
        y += 110
    chrome(d, n, total)
    return im

def card_frame(kind, n, total, typed="", chips=0):
    im = background()
    d = ImageDraw.Draw(im)
    if kind == "intro":
        d.text((W // 2, 250), "Manuscript", font=BIG, fill=C["fg"], anchor="mm")
        d.text((W // 2, 345), "The language for the agentic era.", font=HEAD, fill=C["acc"], anchor="mm")
        names = ["no GC", "no async", "checked effects", "native speed"]
    else:
        d.text((W // 2, 200), "Try it.", font=BIG, fill=C["fg"], anchor="mm")
        d.rounded_rectangle([250, 280, W - 250, 360], 14, fill=C["card"], outline=C["edge"], width=2)
        d.text((290, 298), "$", font=HEAD, fill=C["ok"])
        d.text((345, 298), typed, font=HEAD, fill=C["fg"])
        d.text((W // 2, 410), URL, font=SUB, fill=C["dim"], anchor="mm")
        names = ["verify", "test", "bench", "profile", "diagram", "build"]
    x = W // 2 - sum(SUB.getlength(t) + 52 for t in names) // 2
    y = 500
    for i, t in enumerate(names):
        w = SUB.getlength(t) + 36
        shown = i < chips
        d.rounded_rectangle([x, y, x + w, y + 46], 23, fill=C["bar"] if shown else None, outline=C["acc"] if shown else C["edge"], width=2)
        if shown:
            d.text((x + 18, y + 10), t, font=SUB, fill=C["fg"])
        x += w + 16
    chrome(d, n, total)
    return im

def run(cmd, cwd, ms_dir):
    env = dict(os.environ, PATH=ms_dir + os.pathsep + os.environ["PATH"], NO_COLOR="1")
    p = subprocess.run(cmd, shell=True, executable="/bin/bash", cwd=cwd, env=env, capture_output=True, text=True)
    return [l.replace("\t", "  ").rstrip() for l in (p.stdout + p.stderr).replace(cwd + "/", "").splitlines()]

def wrap(lines, cut, width=COLS):
    out = []
    for l in lines:
        if cut and cut in l:
            l = l.split(cut)[0] + (" …" if cut == ";" else "")
        out += textwrap.wrap(l, width, subsequent_indent="  ", drop_whitespace=False) or [""]
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ms", default="target/release/ms")
    ap.add_argument("-o", "--output", default=os.path.join(HERE, "../static/images/screencast.gif"))
    ap.add_argument("--mp4", help="also write an H.264 MP4 (needs ffmpeg)")
    ap.add_argument("--width", type=int, default=1024, help="GIF width in pixels")
    a = ap.parse_args()
    ms_dir = os.path.dirname(os.path.abspath(a.ms))
    work = tempfile.mkdtemp()
    try:
        for f in os.listdir(SRC):
            shutil.copy(os.path.join(SRC, f), work)
        frames, durs = [], []
        def add(im, ms): frames.append(im); durs.append(ms)
        total = len(SCENES) + 2
        read = lambda text: 220 + 18 * len(text.strip()) if text.strip() else 120
        add(card_frame("intro", 0, total), 1200)
        for i, chips in enumerate(range(1, 5)):
            add(card_frame("intro", 0, total, chips=chips), 350)
        durs[-1] += 1400
        for n, sc in enumerate(SCENES, 1):
            if sc.get("chart"):
                add(chart_frame(sc, n, total, 0), 1100)
                for k in range(1, len(KERNELS) + 1):
                    add(chart_frame(sc, n, total, k), 450)
                durs[-1] += 2600
                continue
            if sc.get("points"):
                add(points_frame(sc, n, total, 0), 900)
                for k in range(1, len(sc["points"]) + 1):
                    add(points_frame(sc, n, total, k), 2600)
                durs[-1] += 1800
                continue
            phases = sc.get("phases") or [sc]
            codes = [open(os.path.join(SRC, ph["src"])).read().rstrip("\n").split("\n") if ph.get("src") else [] for ph in phases]
            raws = [[keep(run(cmd, work, ms_dir)) for cmd, keep in ph["steps"]] for ph in phases]
            room = CARD[3] - CARD[1] - 62 - 34
            for font in FONTS:
                cols = int((CARD[2] - CARD[0] - 64) / font[1])
                outs = [[wrap(raw, ph.get("cut"), cols) for raw in rs] for ph, rs in zip(phases, raws)]
                need = max(len(c) + (0.35 if c else 0) + sum(1 + len(o) for o in os_) for c, os_ in zip(codes, outs))
                if need * font[2] <= room:
                    break
            else:
                print(f"warning: {sc['title']} may not fit", file=sys.stderr)
            sc["_font"] = font
            prev = None
            for pi, (ph, code, phase_outs) in enumerate(zip(phases, codes, outs)):
                sc["_sub"] = ph.get("sub", sc["sub"])
                if prev is None:
                    add(scene_frame(sc, n, total, code, 0, [], False), 1100)
                    visible = set()
                else:
                    visible = {i for i, line in enumerate(code) if line in prev}
                    add(scene_frame(sc, n, total, code, set(visible), [], False), 1400)
                for i, line in enumerate(code):
                    if i in visible: continue
                    visible.add(i)
                    add(scene_frame(sc, n, total, code, set(visible), [], True), read(line))
                if code: durs[-1] += 700
                rows = []
                for (cmd, _), out in zip(ph["steps"], phase_outs):
                    step = max(1, len(cmd) // 6)
                    for k in range(step, len(cmd), step):
                        add(scene_frame(sc, n, total, code, set(visible), rows + [("cmd", cmd[:k])], True), 70)
                    rows = rows + [("cmd", cmd)]
                    add(scene_frame(sc, n, total, code, set(visible), rows, True), 450)
                    for line in out:
                        kind = "err" if re.search(r"error|warning|type:|resolution:", line) else "out"
                        if line.startswith("  ") and rows and rows[-1][0] in ("err", "out"):
                            kind = rows[-1][0]
                        rows = rows + [(kind, line)]
                        add(scene_frame(sc, n, total, code, set(visible), rows, False), 400 + 10 * len(line))
                durs[-1] += ph.get("hold", 2200)
                prev = set(code)
        add(card_frame("outro", total - 1, total), 900)
        cmd = "ms init hello"
        for k in range(2, len(cmd) + 1, 2):
            add(card_frame("outro", total - 1, total, cmd[:k]), 80)
        add(card_frame("outro", total - 1, total, cmd), 500)
        for chips in range(1, 7):
            add(card_frame("outro", total - 1, total, cmd, chips), 280)
        durs[-1] += 2800
        # GIF: scale, quantize, write
        h = int(a.width * H / W)
        scaled = [f.resize((a.width, h), Image.LANCZOS) for f in frames]
        # one fixed palette made from the theme (exact colours plus anti-aliasing blends) keeps accents vivid
        mix = lambda x, y, k: tuple(int(p + (q - p) * k) for p, q in zip(x, y))
        entries = [mix(C["top"], C["bot"], i / 31) for i in range(32)]
        entries += [C["card"], C["bar"], C["edge"], (237, 106, 94), (245, 191, 79), (97, 197, 84)]
        for name in ("fg", "dim", "acc", "acc2", "ok", "err", "kw", "st", "nu", "co"):
            for base in (C["card"], C["top"], C["bot"], C["bar"]):
                entries += [mix(base, C[name], k) for k in (0.25, 0.5, 0.75, 1.0)]
        entries = list(dict.fromkeys(entries))[:256]
        pal = Image.new("P", (1, 1))
        pal.putpalette([c for e in entries + [entries[0]] * (256 - len(entries)) for c in e])
        small = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in scaled]
        os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
        small[0].save(a.output, save_all=True, append_images=small[1:], duration=durs, loop=0, optimize=True, disposal=1)
        print(f"{a.output}: {len(frames)} frames, {sum(durs) / 1000:.0f} s, {os.path.getsize(a.output) // 1024} KB")
        if a.mp4:
            fl = os.path.join(work, "frames.txt")
            with open(fl, "w") as f:
                for i, (im, ms) in enumerate(zip(frames, durs)):
                    p = os.path.join(work, f"f{i:04d}.png"); im.save(p)
                    f.write(f"file '{p}'\nduration {ms / 1000}\n")
                f.write(f"file '{p}'\n")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", fl, "-vf", "fps=30,format=yuv420p",
                            "-c:v", "libx264", "-crf", "20", "-movflags", "+faststart", a.mp4], check=True)
            print(f"{a.mp4}: {os.path.getsize(a.mp4) // 1024} KB")
    finally:
        shutil.rmtree(work)

if __name__ == "__main__":
    sys.exit(main())
