# Generator for c44-unified-diff. Deterministic; run: ms run bench/agent/gen.ms -- c44
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"
import words from "../../lib/text.ms"

# One line of an edit script: a mark (space, `-` or `+`) and the text.
type Op:
    mark: String
    text: String

fn script(a: List[String], b: List[String]) List[Op]:
    let n = a.length()
    let m = b.length()
    var table = List[List[Int]]()
    for _i in 0..n + 2:
        var row = List[Int]()
        for _j in 0..m + 2: row.append(0)
        table.append(row)
    var i = n - 1
    while i >= 0:
        var j = m - 1
        while j >= 0:
            if a[i] == b[j]:
                table[i][j] = table[i + 1][j + 1] + 1
            else:
                table[i][j] = if table[i + 1][j] > table[i][j + 1]: table[i + 1][j] else: table[i][j + 1]
            j -= 1
        i -= 1
    var ops = List[Op]()
    var x = 0
    var y = 0
    while x < n or y < m:
        if x < n and y < m and a[x] == b[y]:
            ops.append(Op(" ", a[x].clone()))
            x += 1
            y += 1
        else if y == m or (x < n and table[x + 1][y] >= table[x][y + 1]):
            ops.append(Op("-", a[x].clone()))
            x += 1
        else:
            ops.append(Op("+", b[y].clone()))
            y += 1
    return ops

fn rng(start: Int, ln: Int) String:
    let s = start + (if ln > 0: 1 else: 0)
    return if ln == 1: "{s}" else: "{s},{ln}"

fn solve(s: String) String:
    var lines = s.split("\n")
    if not lines.is_empty() and lines[lines.length() - 1] == "": lines.pop()
    let head = words(lines[0])
    let c = head[2].parse_int().get(0)
    let n = head[3].parse_int().get(0)
    let m = head[4].parse_int().get(0)
    let a = lines.slice(1, 1 + n).get([])
    let b = lines.slice(1 + n, 1 + n + m).get([])
    let ops = script(a, b)
    var changed = List[Int]()
    for k in 0..ops.length():
        if ops[k].mark != " ": changed.append(k)
    if changed.is_empty(): return ""

    var groups = List[List[Int]]()
    var cur = [changed[0]]
    for k in changed.slice(1, changed.length()).get([]):
        if k - cur[cur.length() - 1] - 1 <= 2 * c:
            cur.append(k)
        else:
            groups.append(cur.clone())
            cur = [k]
    groups.append(cur.clone())
    var out = ["--- {head[0]}", "+++ {head[1]}"]
    for g in groups:
        let lo = if g[0] - c > 0: g[0] - c else: 0
        let hi = if g[g.length() - 1] + 1 + c < ops.length(): g[g.length() - 1] + 1 + c else: ops.length()
        let before = ops.slice(0, lo).get([])
        let sa = before.count(fn o: o.mark != "+")
        let sb = before.count(fn o: o.mark != "-")
        let body = ops.slice(lo, hi).get([])
        let la = body.count(fn o: o.mark != "+")
        let lb = body.count(fn o: o.mark != "-")
        out.append("@@ -{rng(sa, la)} +{rng(sb, lb)} @@")
        for o in body: out.append(o.mark + o.text)
    return out.map(fn x: x + "\n").join("")

fn mk(a: List[String], b: List[String], c: Int, na: String, nb: String) String:
    return "{na} {nb} {c} {a.length()} {b.length()}\n" + a.concat(b).map(fn x: x + "\n").join("")

fn case3(name: String, a: List[String], b: List[String], c: Int) GenCase:
    let s = mk(a, b, c, "a.txt", "b.txt")
    return make_case(name, s, solve(s))

fn words_pool() List[String]:
    return ["alpha", "beta", "gamma", "delta", "eps", "zeta", "eta", "theta", "iota", "kappa", "", "  indented", "trailing ", "- dash", "+ plus", "@@ -1 +1 @@", "--- x", " ", "a b  c"]

fn doc(var rnd: Random, n: Int) List[String]:
    var out = List[String]()
    let pool = words_pool()
    for _i in 0..n: out.append(rnd.choice(pool))
    return out

fn edit(var rnd: Random, a: List[String], k: Int) List[String]:
    var b = a.clone()
    let pool = words_pool()
    for _i in 0..k:
        let r = rnd.random()
        let p = rnd.randrange(0, b.length() + 1)
        let at = if p < b.length() - 1: p else: b.length() - 1
        if r < 0.35 and not b.is_empty():
            b.remove(at)
        else if r < 0.7:
            b.insert(p, rnd.choice(pool))
        else if not b.is_empty():
            b[at] = rnd.choice(pool)
    return b

# `base` with the lines at `changes[k].0` replaced by `changes[k].1`.
fn at(base: List[String], places: List[Int], values: List[String]) List[String]:
    var out = base.clone()
    for k in 0..places.length(): out[places[k]] = values[k].clone()
    return out

export fn gen_c44() Unit:
    var rnd = seeded(44)
    let nums = (1..41).map(fn i: "line {i}")
    let base20 = (1..21).map(fn i: "l{i}")
    let ex_a = ["one", "two", "three", "four", "five", "six"]
    let ex_b = ["one", "two", "3", "four", "five", "seven"]
    let examples = [make_case("basic", mk(ex_a, ex_b, 1, "old.txt", "new.txt"), solve(mk(ex_a, ex_b, 1, "old.txt", "new.txt")))]
    let big_a = doc(var rnd, 280)
    let big_b = edit(var rnd, big_a, 45)
    let small_a = doc(var rnd, 25)
    let small_b = edit(var rnd, small_a, 6)
    let odd_a = ["", " ", "- dash", "+ plus", "@@ -1 +1 @@", "--- hdr", "  two  ", "tab\there"]
    let odd_b = ["", "- dash", "+ plus!", "@@ -1 +1 @@", "+++ hdr", "  two  ", "tab\there", ""]
    let odd = mk(odd_a, odd_b, 2, "x", "z")
    let hidden = examples.concat([
        case3("identical", base20, base20, 3),
        case3("both-empty", [], [], 3),
        case3("a-empty", [], ["x", "y", "z"], 3),
        case3("b-empty", ["x", "y", "z"], [], 3),
        case3("single-middle", nums, at(nums, [19], ["CHANGED"]), 3),
        case3("start-and-end", nums, ["new first"].concat(nums.slice(0, nums.length() - 1).get([])).concat(["new last"]), 3),
        case3("gap-exactly-2c", base20, at(base20, [4, 11], ["X", "Y"]), 3),
        case3("gap-2c-plus-1", base20, at(base20, [4, 12], ["X", "Y"]), 3),
        case3("context-0", base20, at(base20, [2, 3, 9, 15], ["A", "B", "C", "D"]), 0),
        case3("context-0-ins-del", ["a", "b", "c", "d"], ["a", "x", "y", "c", "d", "e"], 0),
        case3("context-1", base20, at(base20, [0, 2, 5, 19], ["S", "T", "U", "V"]), 1),
        case3("context-huge", base20, at(base20, [2, 17], ["A", "B"]), 100),
        case3("pure-insert-delete", base20, base20.slice(0, 5).get([]).concat(["i1", "i2"]).concat(base20.slice(5, 12).get([])).concat(base20.slice(14, 20).get([])), 2),
        case3("repeated-tiebreak", ["a", "a", "b", "a", "a"], ["a", "b", "a"], 1),
        case3("repeated-tiebreak-2", ["x", "y", "x", "y", "x"], ["y", "x", "y", "x", "y"], 0),
        case3("swap-blocks", ["p", "q", "r", "s", "t", "u"], ["t", "u", "r", "s", "p", "q"], 1),
        make_case("odd-lines", odd, solve(odd)),
        case3("single-line-files", ["only"], ["other"], 3),
        case3("single-line-same-ctx", ["same"], ["same", "added"], 3),
        case3("random-small", small_a, small_b, 2),
        case3("random-large", big_a, big_b, 3)
    ])
    write_cases("c44-unified-diff", examples, hidden)
