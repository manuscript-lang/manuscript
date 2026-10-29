import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import {max, min} from "@std/math.ms"

let BAD = "error: bad command"

# Value of a 1-to-6 digit unsigned decimal token, or -1 when the token is malformed.
fn num(t: String) Int:
    if t.length() == 0 or t.length() > 6: return -1
    if not "0123456789".contains(t.get(0)): return -1

    return t.parse_int().get(-1)

fn zeros(n: Int) List[Int]:
    var xs = List[Int]()
    for ignored in 0..n: xs.append(0)
    return xs

fn lcs(a: String, b: String) Int:
    let x = a.to_bytes()
    let y = b.to_bytes()
    var prev = zeros(y.length() + 1)

    for i in 0..x.length():
        var cur = zeros(y.length() + 1)

        for j in 0..y.length():
            if x.get(i) == y.get(j):
                cur[j + 1] = prev[j] + 1
            else:
                cur[j + 1] = max(prev[j + 1], cur[j])

        prev = cur

    return prev[y.length()]

fn edit(a: String, b: String) Int:
    let x = a.to_bytes()
    let y = b.to_bytes()
    var prev = List[Int]()
    for j in 0..y.length() + 1: prev.append(j)

    for i in 0..x.length():
        var cur = List[Int]()
        cur.append(i + 1)

        for j in 0..y.length():
            let cost = if x.get(i) == y.get(j): 0 else: 1

            cur.append(min(prev[j] + cost, min(prev[j + 1] + 1, cur[j] + 1)))

        prev = cur

    return prev[y.length()]

fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
    var total = 0
    for w in ws: total += w

    let top = min(cap, total)
    var dp = zeros(top + 1)

    for i in 0..ws.length():
        let w = ws[i]
        if w > top: continue

        for k in 0..top - w + 1:
            let c = top - k
            dp[c] = max(dp[c], dp[c - w] + vs[i])

    return dp[top]

fn coins(amount: Int, cs: List[Int]) String:
    var dp = List[Int]()
    dp.append(0)

    for a in 1..amount + 1:
        var best = -1

        for c in cs:
            if c <= a and dp[a - c] >= 0:
                let cand = dp[a - c] + 1
                if best < 0 or cand < best: best = cand

        dp.append(best)

    if dp[amount] < 0: return "impossible"

    return "{dp[amount]}"

fn run(line: String) String:
    let t = line.split(" ")
    let cmd = t[0]

    if cmd == "lcs" or cmd == "edit":
        if t.length() != 3 or t[1].length() == 0 or t[2].length() == 0: return BAD
        if cmd == "lcs": return "{lcs(t[1], t[2])}"

        return "{edit(t[1], t[2])}"

    if cmd == "knap":
        if t.length() < 2: return BAD

        let cap = num(t[1])
        if cap < 0: return BAD

        var ws = List[Int]()
        var vs = List[Int]()

        for k in 2..t.length():
            let parts = t[k].split(":")
            if parts.length() != 2: return BAD

            let w = num(parts[0])
            let v = num(parts[1])
            if w < 1 or v < 0: return BAD

            ws.append(w)
            vs.append(v)

        return "{knap(cap, ws, vs)}"

    if cmd == "coins":
        if t.length() < 3: return BAD

        let amount = num(t[1])
        if amount < 0: return BAD

        var cs = List[Int]()

        for k in 2..t.length():
            let c = num(t[k])
            if c < 1: return BAD

            cs.append(c)

        return coins(amount, cs)

    return BAD

fn is_blank(line: String) Bool:
    for t in line.split(" "):
        if t.length() > 0: return false
    return true

export fn main() Int:
    var out = stdout()

    if let lines = read_lines(stdin()):
        for line in lines:
            if is_blank(line): continue

            out.write("{run(line)}\n").get()

    return 0
