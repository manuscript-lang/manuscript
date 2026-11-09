import stdin from "@std/io/io.ms"
import stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

let BAD = "error: bad command"
let INF = 1000000000

fn zeros(n: Int) List[Int]:
    var xs = List[Int]()
    for _i in 0..n:
        xs.append(0)
    return xs

// Parses 1 to 6 ASCII digits with value >= min. Returns -1 when invalid.
fn parse_num(t: String, min: Int) Int:
    let b = t.as_bytes()
    let n = b.length()
    if n < 1 or n > 6:
        return -1

    var v = 0

    for i in 0..n:
        let c = b.get(i).to_int()
        if c < 48 or c > 57:
            return -1

        v = v * 10 + (c - 48)

    if v < min:
        return -1

    return v

fn lcs(a: String, b: String) Int:
    let x = a.as_bytes()
    let y = b.as_bytes()
    let n = x.length()
    let m = y.length()
    var dp = zeros(m + 1)

    for i in 0..n:
        var diag = 0

        for j in 1..m + 1:
            let up = dp[j]

            if x.get(i) == y.get(j - 1):
                dp[j] = diag + 1
            else:
                dp[j] = up.max(dp[j - 1])

            diag = up

    return dp[m]

fn edit(a: String, b: String) Int:
    let x = a.as_bytes()
    let y = b.as_bytes()
    let n = x.length()
    let m = y.length()
    var dp = List[Int]()
    for j in 0..m + 1:
        dp.append(j)

    for i in 1..n + 1:
        var diag = dp[0]
        dp[0] = i

        for j in 1..m + 1:
            let up = dp[j]
            var cost = 1
            if x.get(i - 1) == y.get(j - 1):
                cost = 0

            var best = diag + cost
            if up + 1 < best:
                best = up + 1
            if dp[j - 1] + 1 < best:
                best = dp[j - 1] + 1
            dp[j] = best
            diag = up

    return dp[m]

fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
    var total = 0
    for w in ws:
        total += w

    let size = cap.min(total)
    var dp = zeros(size + 1)

    for k in 0..ws.length():
        let w = ws[k]
        let v = vs[k]

        if w <= size:
            var c = size

            while c >= w:
                let cand = dp[c - w] + v
                if cand > dp[c]:
                    dp[c] = cand
                c -= 1

    return dp[size]

// Returns -1 when impossible.
fn coins(amount: Int, cs: List[Int]) Int:
    var dp = List[Int]()
    dp.append(0)
    for _a in 0..amount:
        dp.append(INF)

    for k in 0..cs.length():
        let c = cs[k]

        if c <= amount:
            for a in c..amount + 1:
                let cand = dp[a - c] + 1
                if cand < dp[a]:
                    dp[a] = cand

    if dp[amount] >= INF:
        return -1

    return dp[amount]

fn run_cmd(toks: List[String]) String:
    let n = toks.length()
    let cmd = toks[0]

    if cmd == "lcs" or cmd == "edit":
        if n != 3 or toks[1].length() == 0 or toks[2].length() == 0:
            return BAD
        if cmd == "lcs":
            return "{lcs(toks[1], toks[2])}"

        return "{edit(toks[1], toks[2])}"

    if cmd == "knap":
        if n < 2:
            return BAD

        let cap = parse_num(toks[1], 0)
        if cap < 0:
            return BAD

        var ws = List[Int]()
        var vs = List[Int]()

        for k in 2..n:
            let parts = toks[k].split(":")
            if parts.length() != 2:
                return BAD

            let w = parse_num(parts[0], 1)
            let v = parse_num(parts[1], 0)
            if w < 0 or v < 0:
                return BAD

            ws.append(w)
            vs.append(v)

        return "{knap(cap, ws, vs)}"

    if cmd == "coins":
        if n < 3:
            return BAD

        let amount = parse_num(toks[1], 0)
        if amount < 0:
            return BAD

        var cs = List[Int]()

        for k in 2..n:
            let c = parse_num(toks[k], 1)
            if c < 0:
                return BAD

            cs.append(c)

        let r = coins(amount, cs)
        if r < 0:
            return "impossible"

        return "{r}"

    return BAD

// Returns none for a blank line (empty or only spaces), which produces no output.
fn run(line: String) String?:
    let b = line.as_bytes()
    var blank = true
    for i in 0..b.length():
        if b.get(i) != 32:
            blank = false
    if blank:
        return none

    let toks = line.split(" ")
    return run_cmd(toks)

export fn main() Int:
    var rs = lines(stdin())
    var out = stdout()

    while true:
        let item = rs.next().get()

        if let line = item:
            if let res = run(line):
                out.write("{res}\n").get()
        else:
            break

    out.flush().get()
    return 0
