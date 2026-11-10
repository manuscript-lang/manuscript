import (
    stdin from "@std/io/io.ms",
    lines from "@std/io/streams.ms",
    Bytes from "@std/bytes.ms",
    max from "@std/math/math.ms",
)

INF := 1000000000
BAD := "error: bad command"

// Parses 1..6 ASCII digits; returns -1 when the text is not such a number.
fn num(t: String) Int:
    n := t.length()
    if n < 1 or n > 6: return -1

    var v = 0

    for i in 0..n:
        c := t.scalar_at(i)
        if c < 48 or c > 57: return -1

        v = v * 10 + (c - 48)

    return v

fn mn(a: Int, b: Int) Int:
    if a < b: return a

    return b

fn is_blank(s: String) Bool:
    for i in 0..s.length():
        if s.get(i) != " ": return false
    return true

fn lcs_len(a: Bytes, b: Bytes) Int:
    n := a.length()
    m := b.length()
    var prev = List[Int]()
    var cur = List[Int]()

    for j in 0..m + 1:
        prev.append(0)
        cur.append(0)

    for i in 0..n:
        cur[0] = 0

        for j in 0..m:
            if a.get(i) == b.get(j):
                cur[j + 1] = prev[j] + 1
            else:
                cur[j + 1] = max(prev[j + 1], cur[j])

        for j in 0..m + 1:
            prev[j] = cur[j]

    return prev[m]

fn edit_dist(a: Bytes, b: Bytes) Int:
    n := a.length()
    m := b.length()
    var prev = List[Int]()
    var cur = List[Int]()

    for j in 0..m + 1:
        prev.append(j)
        cur.append(0)

    for i in 0..n:
        cur[0] = i + 1

        for j in 0..m:
            var cost = 1
            if a.get(i) == b.get(j): cost = 0
            cur[j + 1] = mn(mn(prev[j] + cost, prev[j + 1] + 1), cur[j] + 1)

        for j in 0..m + 1:
            prev[j] = cur[j]

    return prev[m]

// ws and vs are parallel lists of item weights (>= 1) and values (>= 0).
fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
    var total = 0
    for w in ws:
        total += w

    var c = cap
    if total < c: c = total

    var dp = List[Int]()
    for i in 0..c + 1:
        dp.append(0)

    for k in 0..ws.length():
        w := ws[k]
        v := vs[k]

        if w <= c:
            var j = c

            while j >= w:
                cand := dp[j - w] + v
                if cand > dp[j]: dp[j] = cand
                j -= 1

    return dp[c]

// Returns -1 when the amount cannot be formed.
fn coin_count(amount: Int, cs: List[Int]) Int:
    var dp = List[Int]()
    dp.append(0)
    for i in 1..amount + 1:
        dp.append(INF)
    for i in 1..amount + 1:
        for c in cs:
            if c <= i and dp[i - c] + 1 < dp[i]:
                dp[i] = dp[i - c] + 1
    if dp[amount] >= INF: return -1

    return dp[amount]

fn solve(line: String) String:
    toks := line.split(" ")
    n := toks.length()
    cmd := toks[0]

    if cmd == "lcs" or cmd == "edit":
        if n != 3 or toks[1].length() == 0 or toks[2].length() == 0: return BAD
        if cmd == "lcs": return "{lcs_len(toks[1].as_bytes(), toks[2].as_bytes())}"

        return "{edit_dist(toks[1].as_bytes(), toks[2].as_bytes())}"

    if cmd == "knap":
        if n < 2: return BAD

        cap := num(toks[1])
        if cap < 0: return BAD

        var ws = List[Int]()
        var vs = List[Int]()

        for k in 2..n:
            parts := toks[k].split(":")
            if parts.length() != 2: return BAD

            w := num(parts[0])
            v := num(parts[1])
            if w < 1 or v < 0: return BAD

            ws.append(w)
            vs.append(v)

        return "{knap(cap, ws, vs)}"

    if cmd == "coins":
        if n < 3: return BAD

        amount := num(toks[1])
        if amount < 0: return BAD

        var cs = List[Int]()

        for k in 2..n:
            c := num(toks[k])
            if c < 1: return BAD

            cs.append(c)

        r := coin_count(amount, cs)
        if r < 0: return "impossible"

        return "{r}"

    return BAD

fn run() Unit!:
    for line in lines(stdin()):
        if is_blank(line): continue

        print(solve(line))

    return ok(unit)

export fn main() Int:
    run().get()
    return 0
