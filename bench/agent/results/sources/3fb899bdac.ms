import read_lines from "@std/streams.ms"
import stdin, stdout from "@std/io.ms"
import values from "@std/bytes.ms"

let BAD = "error: bad command"
let INF = 1000000000

# Returns the value of a 1-6 digit decimal token, or -1 when malformed.
fn num(t: String) Int:
    if t.length() < 1 or t.length() > 6:
        return -1

    var n = 0

    for b in values(t.to_bytes()):
        let d = b.to_int()
        if d < 48 or d > 57:
            return -1

        n = n * 10 + (d - 48)

    return n

fn blank(line: String) Bool:
    for b in values(line.to_bytes()):
        if b.to_int() != 32:
            return false
    return true

fn lcs(a: List[UInt8], b: List[UInt8]) Int:
    let m = b.length()
    let size = m + 1
    var prev = List[Int](reserve: size)
    for j in 0..size:
        prev.append(0)

    for i in 0..a.length():
        var cur = List[Int](reserve: size)
        cur.append(0)

        for j in 0..m:
            if a[i] == b[j]:
                cur.append(prev[j] + 1)
            else:
                let skip = prev[j + 1].max(cur[j])
                cur.append(skip)

        prev = cur

    return prev[m]

fn edit(a: List[UInt8], b: List[UInt8]) Int:
    let m = b.length()
    let size = m + 1
    var prev = List[Int](reserve: size)
    for j in 0..size:
        prev.append(j)

    for i in 0..a.length():
        var cur = List[Int](reserve: size)
        cur.append(i + 1)

        for j in 0..m:
            var cost = 1
            if a[i] == b[j]:
                cost = 0

            let diag = prev[j] + cost
            let up = prev[j + 1] + 1
            let left = cur[j] + 1
            let best = diag.min(up).min(left)
            cur.append(best)

        prev = cur

    return prev[m]

fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
    var total = 0
    for w in ws:
        total += w

    var top = cap
    if total < cap:
        top = total

    let size = top + 1
    var dp = List[Int](reserve: size)
    for i in 0..size:
        dp.append(0)

    for k in 0..ws.length():
        let w = ws[k]
        let v = vs[k]
        var c = top

        while c >= w:
            let cand = dp[c - w] + v
            if cand > dp[c]:
                dp[c] = cand
            c -= 1

    return dp[top]

# Returns the minimum coin count, or -1 when the amount cannot be made.
fn coins(amount: Int, cs: List[Int]) Int:
    let size = amount + 1
    var dp = List[Int](reserve: size)
    dp.append(0)

    for x in 1..size:
        var best = INF
        for c in cs:
            if c <= x:
                if dp[x - c] < INF:
                    best = best.min(dp[x - c] + 1)
        dp.append(best)

    if dp[amount] >= INF:
        return -1

    return dp[amount]

fn run(line: String) String:
    let t = line.split(" ")
    let n = t.length()
    if n == 0:
        return BAD

    let cmd = t[0]

    if cmd == "lcs" or cmd == "edit":
        if n != 3 or t[1].length() == 0 or t[2].length() == 0:
            return BAD

        let a = values(t[1].to_bytes())
        let b = values(t[2].to_bytes())
        if cmd == "lcs":
            return "{lcs(a, b)}"

        return "{edit(a, b)}"

    if cmd == "knap":
        if n < 2:
            return BAD

        let cap = num(t[1])
        if cap < 0:
            return BAD

        var ws = List[Int]()
        var vs = List[Int]()

        for k in 2..n:
            let p = t[k].split(":")
            if p.length() != 2:
                return BAD

            let w = num(p[0])
            let v = num(p[1])
            if w < 1 or v < 0:
                return BAD

            ws.append(w)
            vs.append(v)

        return "{knap(cap, ws, vs)}"

    if cmd == "coins":
        if n < 3:
            return BAD

        let amount = num(t[1])
        if amount < 0:
            return BAD

        var cs = List[Int]()

        for k in 2..n:
            let c = num(t[k])
            if c < 1:
                return BAD

            cs.append(c)

        let r = coins(amount, cs)
        if r < 0:
            return "impossible"

        return "{r}"

    return BAD

export fn main() Int:
    let lines = read_lines(stdin()).get()

    for line in lines:
        if blank(line):
            continue

        stdout().write("{run(line)}\n").get()

    return 0
