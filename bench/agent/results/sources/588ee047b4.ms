import stdin from "@std/io/io.ms"
import stdout from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn codes(s: String) List[Int]:
    let b = s.as_bytes()
    var xs = List[Int]()
    for i in 0..b.length():
        xs.append(b.uint8(i).get().to_int())
    return xs

fn is_num(s: String) Bool:
    let b = codes(s)
    if b.length() < 1 or b.length() > 6:
        return false

    for i in 0..b.length():
        if b[i] < 48 or b[i] > 57:
            return false
    return true

fn num(s: String) Int:
    let b = codes(s)
    var v = 0
    for i in 0..b.length():
        v = v * 10 + (b[i] - 48)
    return v

fn is_blank(s: String) Bool:
    for c in codes(s):
        if c != 32:
            return false
    return true

fn zeros(n: Int) List[Int]:
    var xs = List[Int]()
    for _i in 0..n:
        xs.append(0)
    return xs

fn lcs(a: List[Int], b: List[Int]) Int:
    let n = a.length()
    let m = b.length()
    var dp = zeros(m + 1)

    for i in 1..n + 1:
        var diag = 0

        for j in 1..m + 1:
            let up = dp[j]

            if a[i - 1] == b[j - 1]:
                dp[j] = diag + 1
            else:
                dp[j] = if up > dp[j - 1]: up else: dp[j - 1]

            diag = up

    return dp[m]

fn edit(a: List[Int], b: List[Int]) Int:
    let n = a.length()
    let m = b.length()
    var dp = zeros(m + 1)
    for j in 0..m + 1:
        dp[j] = j

    for i in 1..n + 1:
        var diag = dp[0]
        dp[0] = i

        for j in 1..m + 1:
            let up = dp[j]
            var best = diag
            if a[i - 1] != b[j - 1]:
                best = best + 1
            if up + 1 < best:
                best = up + 1
            if dp[j - 1] + 1 < best:
                best = dp[j - 1] + 1
            dp[j] = best
            diag = up

    return dp[m]

fn knap(cap: Int, items: List[String]) Int:
    var ws = List[Int]()
    var vs = List[Int]()
    var total_w = 0

    for it in items:
        let p = it.split(":")
        let w = num(p[0])
        ws.append(w)
        vs.append(num(p[1]))
        total_w += w

    let c_max = if cap < total_w: cap else: total_w
    var dp = zeros(c_max + 1)

    for k in 0..ws.length():
        let w = ws[k]
        let v = vs[k]

        if w <= c_max:
            var c = c_max

            while c >= w:
                let cand = dp[c - w] + v
                if cand > dp[c]:
                    dp[c] = cand
                c -= 1

    return dp[c_max]

fn coins(amount: Int, ds: List[String]) String:
    let inf = 1000000000
    var dp = List[Int]()
    dp.append(0)
    for _i in 1..amount + 1:
        dp.append(inf)

    for d in ds:
        let c = num(d)
        for i in c..amount + 1:
            if dp[i - c] + 1 < dp[i]:
                dp[i] = dp[i - c] + 1

    if dp[amount] >= inf:
        return "impossible"

    return "{dp[amount]}"

fn item_ok(s: String) Bool:
    let p = s.split(":")
    if p.length() != 2:
        return false
    if not is_num(p[0]) or not is_num(p[1]):
        return false

    return num(p[0]) >= 1

fn answer(line: String) String:
    let t = line.split(" ")
    let n = t.length()
    let bad = "error: bad command"
    if t[0] == "lcs" and n == 3 and t[1].length() > 0 and t[2].length() > 0:
        return "{lcs(codes(t[1]), codes(t[2]))}"
    if t[0] == "edit" and n == 3 and t[1].length() > 0 and t[2].length() > 0:
        return "{edit(codes(t[1]), codes(t[2]))}"

    if t[0] == "knap" and n >= 2 and is_num(t[1]):
        var ok = true
        for k in 2..n:
            if not item_ok(t[k]):
                ok = false
        if not ok:
            return bad

        var items = List[String]()
        for k in 2..n:
            items.append(t[k].clone())
        return "{knap(num(t[1]), items)}"

    if t[0] == "coins" and n >= 3 and is_num(t[1]):
        var ok = true
        var ds = List[String]()

        for k in 2..n:
            if not is_num(t[k]) or num(t[k]) < 1:
                ok = false
            else:
                ds.append(t[k].clone())

        if not ok:
            return bad

        return coins(num(t[1]), ds)

    return bad

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var out = List[String]()

    for line in text.split("\n"):
        if is_blank(line):
            continue

        out.append(answer(line))

    if out.length() > 0:
        stdout().write(out.join("\n") + "\n").get()
    return 0
