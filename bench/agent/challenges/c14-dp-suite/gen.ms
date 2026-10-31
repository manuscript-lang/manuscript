# Generator for c14-dp-suite. Deterministic; run: ms run bench/agent/gen.ms -- c14
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"
import full_match from "../../lib/text.ms"

let NUM = "[0-9]\{1,6\}"

fn lcs(a: String, b: String) Int:
    let ys = b.chars()
    var prev = List[Int]()
    for _j in 0..ys.length() + 1: prev.append(0)
    for x in a.chars():
        var cur = [0]
        for j in 0..ys.length():
            cur.append(if x == ys[j]: prev[j] + 1 else: if prev[j + 1] > cur[j]: prev[j + 1] else: cur[j])
        prev = cur
    return prev[prev.length() - 1]

fn edit(a: String, b: String) Int:
    let ys = b.chars()
    var prev = List[Int]()
    for j in 0..ys.length() + 1: prev.append(j)
    var i = 0
    for x in a.chars():
        i += 1
        var cur = [i]
        for j in 1..ys.length() + 1:
            let sub = prev[j - 1] + (if x != ys[j - 1]: 1 else: 0)
            let best = if prev[j] + 1 < cur[j - 1] + 1: prev[j] + 1 else: cur[j - 1] + 1
            cur.append(if sub < best: sub else: best)
        prev = cur
    return prev[prev.length() - 1]

type Thing:
    weight: Int
    value: Int

fn knap(cap: Int, items: List[Thing]) Int:
    var best = List[Int]()
    for _c in 0..cap + 1: best.append(0)
    for item in items:
        var c = cap
        while c >= item.weight:
            let take = best[c - item.weight] + item.value
            if take > best[c]: best[c] = take
            c -= 1
    return best[cap]

fn coins(amount: Int, cs: List[Int]) String:
    let inf = 1000000000
    var best = [0]
    for _a in 0..amount: best.append(inf)
    for a in 1..amount + 1:
        for c in cs:
            if c <= a and best[a - c] + 1 < best[a]: best[a] = best[a - c] + 1
    return if best[amount] >= inf: "impossible" else: "{best[amount]}"

fn solve_line(line: String) String:
    let t = line.split(" ")
    let bad = "error: bad command"
    let cmd = t[0].clone()
    if cmd == "lcs" or cmd == "edit":
        if t.length() != 3 or t[1] == "" or t[2] == "": return bad

        return "{if cmd == "lcs": lcs(t[1], t[2]) else: edit(t[1], t[2])}"
    if cmd == "knap":
        if t.length() < 2 or not full_match(NUM, t[1]): return bad

        var items = List[Thing]()
        for tok in t.slice(2, t.length()).get([]):
            let p = tok.split(":")
            if p.length() != 2 or not full_match(NUM, p[0]) or not full_match(NUM, p[1]) or p[0].parse_int().get(0) < 1: return bad

            items.append(Thing(p[0].parse_int().get(0), p[1].parse_int().get(0)))
        return "{knap(t[1].parse_int().get(0), items)}"
    if cmd == "coins":
        if t.length() < 3: return bad

        let rest = t.slice(1, t.length()).get([])
        if not rest.all(fn x: full_match(NUM, x)): return bad

        let cs = t.slice(2, t.length()).get([]).map(fn x: x.parse_int().get(0))
        if cs.min().get(0) < 1: return bad

        return coins(t[1].parse_int().get(0), cs)
    return bad

fn solve(s: String) String:
    var lines = s.split("\n")
    if not lines.is_empty() and lines[lines.length() - 1] == "": lines.pop()
    return lines.filter(fn l: l.replace(" ", "") != "").map(fn l: solve_line(l) + "\n").join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

fn word(var rnd: Random, n: Int, alpha: List[String]) String:
    var out = ""
    for _i in 0..n: out = out + rnd.choice(alpha)
    return out

export fn gen_c14() Unit:
    var rnd = seeded(14)
    let acgt = ["a", "c", "g", "t"]
    let ab = ["a", "b"]
    var parts = List[String]()
    for _i in 0..50:
        let w = rnd.randint(1, 60)
        parts.append("{w}:{rnd.randint(0, 500)}")
    let items = parts.join(" ")
    let examples = [
        mk("basic", "lcs AGGTAB GXTXAYB\nedit kitten sitting\nknap 10 5:10 4:40 6:30 3:50\ncoins 11 1 2 5\ncoins 3 2\nedit a\nknap 5 0:3\n"),
        mk("small", "lcs abc abc\nedit abc xyz\ncoins 0 7\nknap 0 1:1\n")
    ]
    let big_strings = "lcs {word(var rnd, 300, acgt)} {word(var rnd, 300, acgt)}\nedit {word(var rnd, 250, acgt)} {word(var rnd, 250, acgt)}\nedit {word(var rnd, 300, ab)} {word(var rnd, 10, ab)}\n"
    let hidden = examples.concat([
        mk("lcs-edge", "lcs a b\nlcs a a\nlcs abc cba\nlcs aaaa aa\nlcs abcdef fedcba\nlcs ab ba\n"),
        mk("edit-edge", "edit a a\nedit a b\nedit abc a\nedit a abc\nedit intention execution\nedit sunday saturday\nedit flaw lawn\n"),
        mk("knap-edge", "knap 0 1:5 2:6\nknap 100\nknap 1 1:0\nknap 3 3:7 1:3 2:5\nknap 50 10:60 20:100 30:120\nknap 4 5:100\nknap 5 5:100 5:100\n"),
        mk("coins-edge", "coins 7 2 4\ncoins 7 2 4 7\ncoins 6 1 3 4\ncoins 100 1 5 10 25\ncoins 1 2 3\ncoins 12 12\ncoins 13 4 3\n"),
        mk("bad-lcs-edit", "lcs a\nlcs a b c\nedit \nedit  b\nedit a  b\nLCS a b\nlcs\n"),
        mk("bad-knap", "knap\nknap x 1:1\nknap 5 1\nknap 5 1:\nknap 5 :1\nknap 5 1:1:1\nknap 5 -1:1\nknap 5 1:-1\nknap 5 0:1\nknap 1234567 1:1\nknap 5 1:1234567\nknap 5 1:1  2:2\n"),
        mk("bad-coins", "coins\ncoins 5\ncoins x 1\ncoins 5 0\ncoins 5 1 0\ncoins 5 a\ncoins -5 1\ncoins 5 1  2\n"),
        mk("unknown", "foo a b\nfib 10\n lcs a b\n"),
        mk("blank-lines", "\n  \nlcs ab ab\n\n  \nedit a b\n"),
        mk("big-strings", big_strings),
        mk("big-knap", "knap 800 {items}\nknap 3000 {items}\n"),
        mk("big-coins", "coins 9999 7 13 29 101\ncoins 10000 3 7 11 17 23\ncoins 99999 1000 3\n"),
        mk("no-trailing-newline", "lcs a a\ncoins 4 2")
    ])
    write_cases("c14-dp-suite", examples, hidden)
