import json, random, re, pathlib

NUM = re.compile(r"[0-9]{1,6}")

def lcs(a, b):
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return prev[-1]

def edit(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]

def knap(cap, items):
    best = [0] * (cap + 1)
    for w, v in items:
        for c in range(cap, w - 1, -1):
            best[c] = max(best[c], best[c - w] + v)
    return best[cap]

def coins(amount, cs):
    INF = 10**9
    best = [0] + [INF] * amount
    for a in range(1, amount + 1):
        for c in cs:
            if c <= a and best[a - c] + 1 < best[a]: best[a] = best[a - c] + 1
    return "impossible" if best[amount] >= INF else str(best[amount])

def solve_line(line):
    t = line.split(" ")
    bad = "error: bad command"
    cmd = t[0]
    if cmd in ("lcs", "edit"):
        if len(t) != 3 or t[1] == "" or t[2] == "": return bad
        return str((lcs if cmd == "lcs" else edit)(t[1], t[2]))
    if cmd == "knap":
        if len(t) < 2 or not NUM.fullmatch(t[1]): return bad
        items = []
        for tok in t[2:]:
            m = re.fullmatch(r"([0-9]{1,6}):([0-9]{1,6})", tok)
            if not m or int(m.group(1)) < 1: return bad
            items.append((int(m.group(1)), int(m.group(2))))
        return str(knap(int(t[1]), items))
    if cmd == "coins":
        if len(t) < 3 or not all(NUM.fullmatch(x) for x in t[1:]): return bad
        cs = [int(x) for x in t[2:]]
        if min(cs) < 1: return bad
        return coins(int(t[1]), cs)
    return bad

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return "".join(solve_line(l) + "\n" for l in lines if l.strip(" ") != "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(14)
def word(n, alpha="acgt"): return "".join(rnd.choice(alpha) for _ in range(n))
items = " ".join(f"{rnd.randint(1, 60)}:{rnd.randint(0, 500)}" for _ in range(50))
examples = [
    case("basic", "lcs AGGTAB GXTXAYB\nedit kitten sitting\nknap 10 5:10 4:40 6:30 3:50\ncoins 11 1 2 5\ncoins 3 2\nedit a\nknap 5 0:3\n"),
    case("small", "lcs abc abc\nedit abc xyz\ncoins 0 7\nknap 0 1:1\n"),
]
hidden = examples + [
    case("lcs-edge", "lcs a b\nlcs a a\nlcs abc cba\nlcs aaaa aa\nlcs abcdef fedcba\nlcs ab ba\n"),
    case("edit-edge", "edit a a\nedit a b\nedit abc a\nedit a abc\nedit intention execution\nedit sunday saturday\nedit flaw lawn\n"),
    case("knap-edge", "knap 0 1:5 2:6\nknap 100\nknap 1 1:0\nknap 3 3:7 1:3 2:5\nknap 50 10:60 20:100 30:120\nknap 4 5:100\nknap 5 5:100 5:100\n"),
    case("coins-edge", "coins 7 2 4\ncoins 7 2 4 7\ncoins 6 1 3 4\ncoins 100 1 5 10 25\ncoins 1 2 3\ncoins 12 12\ncoins 13 4 3\n"),
    case("bad-lcs-edit", "lcs a\nlcs a b c\nedit \nedit  b\nedit a  b\nLCS a b\nlcs\n"),
    case("bad-knap", "knap\nknap x 1:1\nknap 5 1\nknap 5 1:\nknap 5 :1\nknap 5 1:1:1\nknap 5 -1:1\nknap 5 1:-1\nknap 5 0:1\nknap 1234567 1:1\nknap 5 1:1234567\nknap 5 1:1  2:2\n"),
    case("bad-coins", "coins\ncoins 5\ncoins x 1\ncoins 5 0\ncoins 5 1 0\ncoins 5 a\ncoins -5 1\ncoins 5 1  2\n"),
    case("unknown", "foo a b\nfib 10\n lcs a b\n"),
    case("blank-lines", "\n  \nlcs ab ab\n\n  \nedit a b\n"),
    case("big-strings", f"lcs {word(300)} {word(300)}\nedit {word(250)} {word(250)}\nedit {word(300, 'ab')} {word(10, 'ab')}\n"),
    case("big-knap", f"knap 800 {items}\nknap 3000 {items}\n"),
    case("big-coins", "coins 9999 7 13 29 101\ncoins 10000 3 7 11 17 23\ncoins 99999 1000 3\n"),
    case("no-trailing-newline", "lcs a a\ncoins 4 2"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
