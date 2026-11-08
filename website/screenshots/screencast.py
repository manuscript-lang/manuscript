#!/usr/bin/env python3
"""Renders the feature screencast GIF used on the docs home page (and reusable in the README).

Usage: python3 website/screenshots/screencast.py [--ms target/release/ms] [--theme dark|light] [-o out.gif]

Every command in SCENES runs for real with the given `ms`, so the output shown is what the
compiler prints. Needs Python 3 with Pillow and the DejaVu Sans Mono font; neither is a
project dependency (see README.md).
"""
import argparse, os, re, textwrap, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "screencast")

# (caption, source file or None, command run in a scratch copy of screencast/ and the demo project)
SCENES = [
    ("One owner per value. No garbage collector.",
     "Use-after-move is a compile error: no GC pauses, no refcounts.",
     "own.ms", "ms run own.ms", 1),
    ("Native speed. Faster than Go on all 7 kernels.",
     "5M sieve: 26 ms vs Go 65 ms, Rust 30 ms (bench/perf, 2026-11-05).",
     None, "ms build sieve.ms -o sieve && ./sieve", 4),
    ("No async. No await.",
     "Any function can run concurrently, so no colored functions to rewrite.",
     "conc.ms", "ms run conc.ms", 4),
    ("Effects are checked. Pure means pure.",
     "A function that prints, reads files or calls out must say so, or lint flags it.",
     "effects.ms", "ms lint effects.ms", 1),
    ("Failure is a value. Cleanup is automatic.",
     "T! and try keep errors in the signature; files close at scope end.",
     "scope.ms", "ms run scope.ms", 2),
    ("Errors that tell you the fix.",
     "Cause and remedy in every diagnostic; --json gives agents the same data.",
     "fixme.ms", "ms check fixme.ms", 1),
    ("See what the agent built.",
     "Call graphs and code maps come from checked source, not guesses.",
     None, "ms diagram conc.ms --format ascii", 7),
    ("One toolchain. Batteries-included stdlib.",
     "Check, format, lint, test and build, with files, HTTP, JSON and crypto in the box.",
     None, "ms verify demo/ms.toml", 4),
]
COLS = int((1000 - 64) / 14.4)

THEMES = {
    "dark": dict(bg=(24, 26, 32), bar=(36, 39, 48), fg=(220, 223, 230), dim=(130, 136, 150), kw=(198, 120, 221),
                 st=(152, 195, 121), nu=(209, 154, 102), co=(110, 118, 135), cap=(97, 175, 239), err=(224, 108, 117), prompt=(152, 195, 121)),
    "light": dict(bg=(250, 249, 245), bar=(236, 233, 224), fg=(40, 42, 54), dim=(120, 120, 130), kw=(160, 50, 160),
                  st=(30, 130, 60), nu=(190, 100, 20), co=(140, 140, 150), cap=(20, 90, 170), err=(190, 40, 50), prompt=(30, 130, 60)),
}
KEYWORDS = set("fn let var if else for in return try import from export type impl while match and or not true false none ok error".split())
W, H, PAD, FS = 1000, 620, 32, 24
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", FS)
BOLD = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 26)
LH = 34
SMALL = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 17)
CW = FONT.getlength("M")

def tokens(line, t):
    if line.lstrip().startswith("//"):
        return [(line, t["co"])]
    out = []
    for m in re.finditer(r'"(?:[^"\\]|\\.)*"|\w+|\s+|.', line):
        s = m.group(0)
        c = t["fg"]
        if s.startswith('"'): c = t["st"]
        elif s in KEYWORDS: c = t["kw"]
        elif s.isdigit(): c = t["nu"]
        out.append((s, c))
    return out

def run(cmd, cwd, ms_dir, limit):
    env = dict(os.environ, PATH=ms_dir + os.pathsep + os.environ["PATH"], NO_COLOR="1")
    p = subprocess.run(cmd, shell=True, cwd=cwd, env=env, capture_output=True, text=True)
    text = (p.stdout + p.stderr).replace(cwd + "/", "")
    lines = [l.rstrip() for l in text.splitlines()][:limit]
    out = []
    for l in lines:
        out += textwrap.wrap(l, COLS, subsequent_indent="  ", drop_whitespace=False) or [""]
    return out

def frame(t, title, benefit, code, shown, cmd, out, n_out, step, total):
    im = Image.new("RGB", (W, H), t["bg"])
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 44], fill=t["bar"])
    for i, c in enumerate([(237, 106, 94), (245, 191, 79), (97, 197, 84)]):
        d.ellipse([18 + i * 24, 15, 32 + i * 24, 29], fill=c)
    d.text((W - PAD, 14), "manuscript", font=FONT, fill=t["dim"], anchor="ra")
    y = 64
    for i, line in enumerate(code[:shown]):
        x = PAD
        for s, c in tokens(line, t):
            d.text((x, y), s, font=FONT, fill=c)
            x += CW * len(s)
        y += LH
    y = 64 + LH * max(len(code), 0) + (10 if code else 0)
    if cmd is not None:
        d.text((PAD, y), "$ ", font=FONT, fill=t["prompt"])
        d.text((PAD + CW * 2, y), cmd, font=FONT, fill=t["fg"])
        y += LH
        for line in out[:n_out]:
            col = t["err"] if re.search(r"error|type:|resolution:", line) else t["fg"]
            d.text((PAD, y), line[:int((W - 2 * PAD) / CW)], font=FONT, fill=col)
            y += LH
    d.rectangle([0, H - 104, W, H], fill=t["bar"])
    d.text((PAD, H - 72), title, font=BOLD, fill=t["cap"], anchor="lm")
    d.text((PAD, H - 34), benefit, font=SMALL, fill=t["fg"], anchor="lm")
    d.text((W - PAD, H - 72), f"{step}/{total}", font=FONT, fill=t["dim"], anchor="rm")
    return im

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ms", default="target/release/ms")
    ap.add_argument("--theme", default="dark", choices=THEMES)
    ap.add_argument("-o", "--output", default=os.path.join(HERE, "../static/images/screencast.gif"))
    a = ap.parse_args()
    t = THEMES[a.theme]
    ms_dir = os.path.dirname(os.path.abspath(a.ms))
    work = tempfile.mkdtemp()
    try:
        for f in os.listdir(SRC):
            shutil.copy(os.path.join(SRC, f), work)
        env = dict(os.environ, PATH=ms_dir + os.pathsep + os.environ["PATH"])
        subprocess.run("ms init demo", shell=True, cwd=work, env=env, capture_output=True, check=True)
        frames, durs = [], []
        total = len(SCENES)
        for i, (title, benefit, srcfile, cmd, limit) in enumerate(SCENES, 1):
            code = open(os.path.join(SRC, srcfile)).read().rstrip("\n").split("\n") if srcfile else []
            out = run(cmd, work, ms_dir, limit)
            def add(shown, c, n, ms):
                frames.append(frame(t, title, benefit, code, shown, c, out, n, i, total)); durs.append(ms)
            # human pacing: a code line every 0.45 s, a short read, then the command and each output line
            for n in range(1, len(code) + 1):
                add(n, None, 0, 450)
            if code: durs[-1] += 900 + sum(len(l) for l in code) * 10
            add(len(code), cmd, 0, 800)
            for n in range(1, len(out)):
                add(len(code), cmd, n, 450)
            add(len(code), cmd, len(out), 2200 + 300 * len(out))
        # quantize with a shared adaptive palette per frame; hold the loop point
        pal = [f.quantize(colors=40, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
        os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
        pal[0].save(a.output, save_all=True, append_images=pal[1:], duration=durs, loop=0, optimize=True, disposal=1)
        print(f"{a.output}: {len(frames)} frames, {os.path.getsize(a.output) // 1024} KB")
    finally:
        shutil.rmtree(work)

if __name__ == "__main__":
    sys.exit(main())
