import json, random, pathlib

def script(a, b):
    n, m = len(a), len(b)
    L = [[0] * (m + 2) for _ in range(n + 2)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            L[i][j] = L[i + 1][j + 1] + 1 if a[i] == b[j] else max(L[i + 1][j], L[i][j + 1])
    ops, i, j = [], 0, 0
    while i < n or j < m:
        if i < n and j < m and a[i] == b[j]:
            ops.append((" ", a[i])); i += 1; j += 1
        elif j == m or (i < n and L[i + 1][j] >= L[i][j + 1]):
            ops.append(("-", a[i])); i += 1
        else:
            ops.append(("+", b[j])); j += 1
    return ops

def rng(start, ln):
    s = start + (1 if ln > 0 else 0)
    return f"{s}" if ln == 1 else f"{s},{ln}"

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    na, nb, c, n, m = lines[0].split()
    c, n, m = int(c), int(n), int(m)
    a, b = lines[1:1 + n], lines[1 + n:1 + n + m]
    ops = script(a, b)
    ch = [k for k, o in enumerate(ops) if o[0] != " "]
    if not ch: return ""
    groups, cur = [], [ch[0]]
    for k in ch[1:]:
        if k - cur[-1] - 1 <= 2 * c: cur.append(k)
        else: groups.append(cur); cur = [k]
    groups.append(cur)
    out = [f"--- {na}", f"+++ {nb}"]
    for g in groups:
        lo = max(0, g[0] - c); hi = min(len(ops), g[-1] + 1 + c)
        before = ops[:lo]
        sa = sum(1 for o in before if o[0] != "+"); sb = sum(1 for o in before if o[0] != "-")
        body = ops[lo:hi]
        la = sum(1 for o in body if o[0] != "+"); lb = sum(1 for o in body if o[0] != "-")
        out.append(f"@@ -{rng(sa, la)} +{rng(sb, lb)} @@")
        out += [o[0] + o[1] for o in body]
    return "".join(x + "\n" for x in out)

def mk(a, b, c=3, na="a.txt", nb="b.txt"):
    return f"{na} {nb} {c} {len(a)} {len(b)}\n" + "".join(x + "\n" for x in a + b)
def case(name, a, b, c=3, na="a.txt", nb="b.txt"):
    s = mk(a, b, c, na, nb)
    return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(44)
W = ["alpha", "beta", "gamma", "delta", "eps", "zeta", "eta", "theta", "iota", "kappa", "", "  indented", "trailing ", "- dash", "+ plus", "@@ -1 +1 @@", "--- x", " ", "a b  c"]
def doc(n, pool=None):
    pool = pool or W
    return [rnd.choice(pool) for _ in range(n)]
def edit(a, k, pool=None):
    b = list(a)
    for _ in range(k):
        r = rnd.random()
        p = rnd.randrange(len(b) + 1)
        if r < .35 and b: del b[min(p, len(b) - 1)]
        elif r < .7: b.insert(p, rnd.choice(pool or W))
        elif b: b[min(p, len(b) - 1)] = rnd.choice(pool or W)
    return b
nums = [f"line {i}" for i in range(1, 41)]

examples = [case("basic", ["one", "two", "three", "four", "five", "six"], ["one", "two", "3", "four", "five", "seven"], 1, "old.txt", "new.txt")]
base20 = [f"l{i}" for i in range(1, 21)]
def at(lst, changes):
    out = list(lst)
    for i, v in changes.items(): out[i] = v
    return out
big_a = doc(280); big_b = edit(big_a, 45)
hidden = examples + [
    case("identical", base20, base20, 3),
    case("both-empty", [], [], 3),
    case("a-empty", [], ["x", "y", "z"], 3),
    case("b-empty", ["x", "y", "z"], [], 3),
    case("single-middle", nums, at(nums, {19: "CHANGED"}), 3),
    case("start-and-end", nums, ["new first"] + nums[:-1] + ["new last"], 3),
    case("gap-exactly-2c", base20, at(base20, {4: "X", 11: "Y"}), 3),   # 6 unchanged between: merge
    case("gap-2c-plus-1", base20, at(base20, {4: "X", 12: "Y"}), 3),    # 7 unchanged between: split
    case("context-0", base20, at(base20, {2: "A", 3: "B", 9: "C", 15: "D"}), 0),
    case("context-0-ins-del", ["a", "b", "c", "d"], ["a", "x", "y", "c", "d", "e"], 0),
    case("context-1", base20, at(base20, {0: "S", 2: "T", 5: "U", 19: "V"}), 1),
    case("context-huge", base20, at(base20, {2: "A", 17: "B"}), 100),
    case("pure-insert-delete", base20, base20[:5] + ["i1", "i2"] + base20[5:12] + base20[14:], 2),
    case("repeated-tiebreak", ["a", "a", "b", "a", "a"], ["a", "b", "a"], 1),
    case("repeated-tiebreak-2", ["x", "y", "x", "y", "x"], ["y", "x", "y", "x", "y"], 0),
    case("swap-blocks", ["p", "q", "r", "s", "t", "u"], ["t", "u", "r", "s", "p", "q"], 1),
    case("odd-lines", ["", " ", "- dash", "+ plus", "@@ -1 +1 @@", "--- hdr", "  two  ", "tab\there"], ["", "- dash", "+ plus!", "@@ -1 +1 @@", "+++ hdr", "  two  ", "tab\there", ""], 2, "x y".split()[0], "z"),
    case("single-line-files", ["only"], ["other"], 3),
    case("single-line-same-ctx", ["same"], ["same", "added"], 3),
    case("random-small", (r := doc(25)), edit(r, 6), 2),
    case("random-large", big_a, big_b, 3),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
