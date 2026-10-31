# Generator for c16-maze-bfs. Deterministic; run: ms run bench/agent/gen.ms -- c16
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"

fn count(text: String, ch: String) Int: text.chars().count(fn c: c == ch)

fn solve(s: String) String:
    var rows = s.split("\n")
    while not rows.is_empty() and rows[rows.length() - 1] == "": rows.pop()
    for r in 0..rows.length():
        let cells = rows[r].chars()
        for c in 0..cells.length():
            if not "#.SE".contains(cells[c]): return "error: bad character at {r + 1},{c + 1}\n"
    if rows.map(fn r: r.length()).distinct().length() > 1: return "error: ragged grid\n"

    let flat = rows.join("")
    if count(flat, "S") == 0: return "error: no start\n"
    if count(flat, "S") > 1: return "error: multiple starts\n"
    if count(flat, "E") == 0: return "error: no end\n"
    if count(flat, "E") > 1: return "error: multiple ends\n"

    let h = rows.length()
    let w = rows[0].length()
    let cells = rows.map(fn r: r.chars())
    var start = 0
    for r in 0..h:
        for c in 0..w:
            if cells[r][c] == "S": start = r * w + c
    var dist = Map[Int, Int]()
    dist[start] = 0
    var queue = [start]
    var head = 0
    while head < queue.length():
        let at = queue[head]
        head += 1
        let r = at / w
        let c = at % w
        if cells[r][c] == "E": return "{dist.get_or(at, 0)}\n"

        for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
            let nr = r + step[0]
            let nc = c + step[1]
            if nr >= 0 and nr < h and nc >= 0 and nc < w and cells[nr][nc] != "#" and not dist.contains(nr * w + nc):
                dist[nr * w + nc] = dist.get_or(at, 0) + 1
                queue.append(nr * w + nc)
    return "no path\n"

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

fn maze(var rnd: Random, h: Int, w: Int, p: Float) String:
    while true:
        var g = List[List[String]]()
        for _r in 0..h:
            var row = List[String]()
            for _c in 0..w: row.append(if rnd.random() < p: "#" else: ".")
            g.append(row)
        g[0][0] = "S"
        g[h - 1][w - 1] = "E"
        let t = g.map(fn r: r.join("")).join("\n") + "\n"
        let verdict = solve(t)
        if "0123456789".contains(verdict.take(1)): return t
    return ""

export fn gen_c16() Unit:
    var rnd = seeded(16)
    let open_big = maze(var rnd, 60, 60, 0.3)
    let examples = [
        mk("basic", "S.#.....\n.##.###.\n....#...\n.####.#.\n......#E\n"),
        mk("no-path", "S#E\n.#.\n.#.\n")
    ]
    let dense = maze(var rnd, 50, 50, 0.38)
    let hidden = examples.concat([
        mk("adjacent", "SE\n"),
        mk("detour", "S.....\n#####.\n......\n.#####\n......\n#####E\n"),
        mk("e-before-s", "E..\n.#.\n..S\n"),
        mk("bad-char-reading-order", "S.?\n.x.\n..E\n"),
        mk("ragged", "S..\n..\n..E\n"),
        mk("bad-char-beats-ragged", "S..\n.\n.@\n"),
        mk("no-start", "...\n..E\n"),
        mk("multiple-starts", "S.S\n..E\n"),
        mk("no-end", "S..\n...\n"),
        mk("empty-input", ""),
        mk("trailing-blank-lines", "S.E\n\n\n"),
        mk("interior-blank-line", "S.E\n\n..\n"),
        mk("random-60x60", open_big),
        mk("random-dense-walls", dense),
        mk("no-trailing-newline", "S.E")
    ])
    write_cases("c16-maze-bfs", examples, hidden)
