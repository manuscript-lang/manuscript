import json, random, pathlib
from collections import deque

def solve(s):
    rows = s.split("\n")
    while rows and rows[-1] == "": rows.pop()
    for r, row in enumerate(rows, 1):
        for c, ch in enumerate(row, 1):
            if ch not in "#.SE": return f"error: bad character at {r},{c}\n"
    if len({len(r) for r in rows}) > 1: return "error: ragged grid\n"
    flat = "".join(rows)
    if flat.count("S") == 0: return "error: no start\n"
    if flat.count("S") > 1: return "error: multiple starts\n"
    if flat.count("E") == 0: return "error: no end\n"
    if flat.count("E") > 1: return "error: multiple ends\n"
    H, W = len(rows), len(rows[0])
    start = next((r, c) for r in range(H) for c in range(W) if rows[r][c] == "S")
    dist = {start: 0}
    q = deque([start])
    while q:
        r, c = q.popleft()
        if rows[r][c] == "E": return f"{dist[(r, c)]}\n"
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < H and 0 <= nc < W and rows[nr][nc] != "#" and (nr, nc) not in dist:
                dist[(nr, nc)] = dist[(r, c)] + 1
                q.append((nr, nc))
    return "no path\n"

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(16)
def maze(H, W, p):
  while True:
    g = [["#" if rnd.random() < p else "." for _ in range(W)] for _ in range(H)]
    g[0][0] = "S"; g[H - 1][W - 1] = "E"
    t = "\n".join("".join(r) for r in g) + "\n"
    if solve(t)[0].isdigit(): return t
open_big = maze(60, 60, 0.3)
examples = [
    case("basic", "S.#.....\n.##.###.\n....#...\n.####.#.\n......#E\n"),
    case("no-path", "S#E\n.#.\n.#.\n"),
]
hidden = examples + [
    case("adjacent", "SE\n"),
    case("detour", "S.....\n#####.\n......\n.#####\n......\n#####E\n"),
    case("e-before-s", "E..\n.#.\n..S\n"),
    case("bad-char-reading-order", "S.?\n.x.\n..E\n"),
    case("ragged", "S..\n..\n..E\n"),
    case("bad-char-beats-ragged", "S..\n.\n.@\n"),
    case("no-start", "...\n..E\n"),
    case("multiple-starts", "S.S\n..E\n"),
    case("no-end", "S..\n...\n"),
    case("empty-input", ""),
    case("trailing-blank-lines", "S.E\n\n\n"),
    case("interior-blank-line", "S.E\n\n..\n"),
    case("random-60x60", open_big),
    case("random-dense-walls", maze(50, 50, 0.38)),
    case("no-trailing-newline", "S.E"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
