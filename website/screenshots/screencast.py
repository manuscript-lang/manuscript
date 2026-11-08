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

# title: "*word*" is highlighted. steps: (command, keep(lines) -> lines shown).
def first(n): return lambda ls: ls[:n]
def last(n): return lambda ls: ls[-n:]
SCENES = [
    dict(title="*One owner.* No garbage collector.",
         sub="Use-after-move is a compile error. No GC pauses, no refcounts.",
         src="own.ms", steps=[("ms run own.ms", first(1))], cut=";"),
    dict(title="*C-class speed.* No GC, no heavy runtime.",
         sub="5M sieve: 26 ms, C 26 ms (bench/perf, 2026-11-05).",
         src=None, steps=[("ms build sieve.ms -o sieve && ./sieve", first(2))]),
    dict(title="*No async.* No await.",
         sub="Any function can run concurrently. Nothing to color or rewrite.",
         src="conc.ms", steps=[("ms run conc.ms", first(1))]),
    dict(title="*Every core*, no threads to manage.",
         sub="Four CPU-bound promises, spread across the machine by the runtime.",
         src=None, steps=[("ms run par.ms", first(1))]),
    dict(title="*Effects* are checked.",
         sub="A function that prints or touches files has to say so.",
         src="effects.ms", steps=[("ms lint effects.ms", first(1))], cut=";"),
    dict(title="Errors that tell you *the fix*.",
         sub="Cause and remedy in every diagnostic. --json for agents.",
         src="fixme.ms", steps=[("ms check fixme.ms", first(1))], cut=";"),
    dict(title="*Test. Bench. Profile.* Built in.",
         sub="No framework, no harness, no extra tools to install.",
         src=None, steps=[
             ("ms test tb.ms", last(1)),
             ("ms bench tb.ms --time 20ms --samples 3", lambda ls: [l for l in ls if l.startswith("BENCH")]),
             ("ms profile prof.ms --out-dir pr --top 3", lambda ls: ls[1:4]),
         ], cut=" ("),
    dict(title="*See what the agent built.*",
         sub="Call graphs and code maps come from checked source.",
         src=None, steps=[("ms diagram conc.ms --format ascii", first(6))]),
]
URL = "manuscript-lang.github.io/manuscript"

W, H = 1280, 720
C = dict(top=(13, 15, 30), bot=(34, 17, 52), card=(18, 20, 32), bar=(30, 33, 50), edge=(60, 66, 96),
         fg=(232, 235, 247), dim=(146, 152, 178), acc=(86, 214, 255), pink=(255, 95, 170), ok=(120, 230, 150),
         err=(255, 110, 125), kw=(255, 121, 198), st=(150, 235, 160), nu=(255, 184, 108), co=(110, 118, 150))
KEYWORDS = set("fn let var if else for in return try import from export type impl while match and or not true false none ok error test bench".split())
D = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono"
CODE, HEAD, SUB, SMALL = (ImageFont.truetype(D + ".ttf", 27), ImageFont.truetype(D + "-Bold.ttf", 47),
                          ImageFont.truetype(D + ".ttf", 22), ImageFont.truetype(D + ".ttf", 17))
BIG = ImageFont.truetype(D + "-Bold.ttf", 104)
CW, LH, CARD = CODE.getlength("M"), 37, (60, 196, 1220, 650)
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

def scene_frame(sc, n, total, code, shown, rows, cursor):
    """rows: list of (kind, text) below the code: 'cmd', 'out', 'err'."""
    im = background()
    d = ImageDraw.Draw(im)
    header(d, sc["title"], sc["sub"])
    terminal(d)
    x0, y = CARD[0] + 32, CARD[1] + 62
    last_y = None
    for i, line in enumerate(code[:shown]):
        x = x0
        for s, c in tokens(line):
            d.text((x, y), s, font=CODE, fill=c)
            x += CW * len(s)
        last_y, last_x = y, x
        y += LH
    if code: y += 12
    for kind, text in rows:
        if kind == "cmd":
            d.text((x0, y), "$", font=CODE, fill=C["ok"])
            d.text((x0 + CW * 2, y), text, font=CODE, fill=C["fg"])
            last_y, last_x = y, x0 + CW * (2 + len(text))
        else:
            d.text((x0, y), text, font=CODE, fill=C["err"] if kind == "err" else C["fg"])
            last_y, last_x = None, 0
        y += LH
    if cursor and last_y is not None:
        d.rectangle([last_x + 3, last_y + 3, last_x + CW * 0.55 + 3, last_y + 29], fill=C["acc"])
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
    p = subprocess.run(cmd, shell=True, cwd=cwd, env=env, capture_output=True, text=True)
    return [l.rstrip() for l in (p.stdout + p.stderr).replace(cwd + "/", "").splitlines()]

def wrap(lines, cut):
    out = []
    for l in lines:
        if cut and cut in l:
            l = l.split(cut)[0] + (" …" if cut == ";" else "")
        out += textwrap.wrap(l, COLS, subsequent_indent="  ", drop_whitespace=False) or [""]
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
            code = open(os.path.join(SRC, sc["src"])).read().rstrip("\\n".replace("\\n", "\n")).split("\n") if sc["src"] else []
            add(scene_frame(sc, n, total, code, 0, [], False), 1100)
            for k, line in enumerate(code, 1):
                add(scene_frame(sc, n, total, code, k, [], True), read(line))
            if code: durs[-1] += 700
            rows = []
            for cmd, keep in sc["steps"]:
                step = max(1, len(cmd) // 6)
                for k in range(step, len(cmd), step):
                    add(scene_frame(sc, n, total, code, len(code), rows + [("cmd", cmd[:k])], True), 70)
                rows = rows + [("cmd", cmd)]
                add(scene_frame(sc, n, total, code, len(code), rows, True), 450)
                out = wrap(keep(run(cmd, work, ms_dir)), sc.get("cut"))
                for line in out:
                    kind = "err" if re.search(r"error|warning|type:|resolution:", line) else "out"
                    rows = rows + [(kind, line)]
                    add(scene_frame(sc, n, total, code, len(code), rows, False), 400 + 10 * len(line))
            durs[-1] += 1300
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
        for name in ("fg", "dim", "acc", "pink", "ok", "err", "kw", "st", "nu", "co"):
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
