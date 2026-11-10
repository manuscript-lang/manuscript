import (
    read_lines from "@std/streams.ms",
    stdin, stdout from "@std/io.ms",
    values from "@std/bytes.ms",
)

BAD := "error: bad command"
INF := 1000000000

// Returns the value of a 1-6 digit decimal token, or -1 when malformed.
fn num(t: String) Int:
    if t.length() < 1 or t.length() > 6: return -1

    var n = 0

    for b in values(t.to_bytes()):
        d := b.to_int()
        if d < 48 or d > 57: return -1

        n = n * 10 + (d - 48)

    return n

fn blank(line: String) Bool:
    for b in values(line.to_bytes()):
        if b.to_int() != 32: return false
    return true

fn lcs(a: List[UInt8], b: List[UInt8]) Int:
    m := b.length()
    size := m + 1
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
                skip := prev[j + 1].max(cur[j])
                cur.append(skip)

        prev = cur

    return prev[m]

fn edit(a: List[UInt8], b: List[UInt8]) Int:
    m := b.length()
    size := m + 1
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

            diag := prev[j] + cost
            up := prev[j + 1] + 1
            left := cur[j] + 1
            best := diag.min(up).min(left)
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

    size := top + 1
    var dp = List[Int](reserve: size)
    for i in 0..size:
        dp.append(0)

    for k in 0..ws.length():
        w := ws[k]
        v := vs[k]
        var c = top

        while c >= w:
            cand := dp[c - w] + v
            if cand > dp[c]:
                dp[c] = cand
            c -= 1

    return dp[top]

// Returns the minimum coin count, or -1 when the amount cannot be made.
fn coins(amount: Int, cs: List[Int]) Int:
    size := amount + 1
    var dp = List[Int](reserve: size)
    dp.append(0)

    for x in 1..size:
        var best = INF
        for c in cs:
            if c <= x:
                if dp[x - c] < INF:
                    best = best.min(dp[x - c] + 1)
        dp.append(best)

    if dp[amount] >= INF: return -1

    return dp[amount]

fn run(line: String) String:
    t := line.split(" ")
    n := t.length()
    if n == 0: return BAD

    cmd := t[0]

    if cmd == "lcs" or cmd == "edit":
        if n != 3 or t[1].length() == 0 or t[2].length() == 0: return BAD

        a := values(t[1].to_bytes())
        b := values(t[2].to_bytes())
        if cmd == "lcs": return "{lcs(a, b)}"

        return "{edit(a, b)}"

    if cmd == "knap":
        if n < 2: return BAD

        cap := num(t[1])
        if cap < 0: return BAD

        var ws = List[Int]()
        var vs = List[Int]()

        for k in 2..n:
            p := t[k].split(":")
            if p.length() != 2: return BAD

            w := num(p[0])
            v := num(p[1])
            if w < 1 or v < 0: return BAD

            ws.append(w)
            vs.append(v)

        return "{knap(cap, ws, vs)}"

    if cmd == "coins":
        if n < 3: return BAD

        amount := num(t[1])
        if amount < 0: return BAD

        var cs = List[Int]()

        for k in 2..n:
            c := num(t[k])
            if c < 1: return BAD

            cs.append(c)

        r := coins(amount, cs)
        if r < 0: return "impossible"

        return "{r}"

    return BAD

export fn main() Int:
    lines := read_lines(stdin()).get()

    for line in lines:
        if blank(line): continue

        stdout().write("{run(line)}\n").get()

    return 0
