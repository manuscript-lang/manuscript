from "@std/bytes.ms" import Bytes
from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

let BAD = "error: bad command"

def is_blank(line: String) -> Bool:
    for i in 0..line.length():
        if line.get(i) != " ": return False
    return True

def is_digit(c: String) -> Bool:
    return c >= "0" and c <= "9"

# Returns the decimal value of a 1-6 digit token, or none.
def number(text: String) -> Optional[Int]:
    if text.length() < 1 or text.length() > 6: return none

    for i in 0..text.length():
        if not is_digit(text.get(i)): return none
    return text.parse_int()

# Like `number`, but -1 marks a malformed token (valid values are never negative).
def value(text: String) -> Int:
    return number(text).get(-1)

def lcs(a: Bytes, b: Bytes) -> Int:
    let n = a.length()
    let m = b.length()
    var prev = List[Int]()
    for _j in 0..m + 1: prev.append(0)

    for i in 1..n + 1:
        var cur = List[Int]()
        cur.append(0)

        for j in 1..m + 1:
            if a.get(i - 1) == b.get(j - 1):
                cur.append(prev[j - 1] + 1)
            else:
                cur.append(prev[j].max(cur[j - 1]))

        prev = cur

    return prev[m]

def edit(a: Bytes, b: Bytes) -> Int:
    let n = a.length()
    let m = b.length()
    var prev = List[Int]()
    for j in 0..m + 1: prev.append(j)

    for i in 1..n + 1:
        var cur = List[Int]()
        cur.append(i)

        for j in 1..m + 1:
            var cost = 1
            if a.get(i - 1) == b.get(j - 1): cost = 0
            cur.append((prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost))

        prev = cur

    return prev[m]

# 0/1 knapsack; only capacities up to the total weight matter, so the table is capped there.
def knap(cap: Int, ws: List[Int], vs: List[Int]) -> Int:
    var total = 0
    for w in ws: total += w

    let limit = cap.min(total)
    var best = List[Int]()
    for _c in 0..limit + 1: best.append(0)

    for i in 0..ws.length():
        let w = ws[i]
        if w > limit: continue

        var c = limit

        while c >= w:
            best[c] = best[c].max(best[c - w] + vs[i])
            c -= 1

    return best[limit]

# Minimum coin count, or -1 when the amount cannot be made.
def coins(amount: Int, cs: List[Int]) -> Int:
    let inf = amount + 1
    var best = List[Int]()
    best.append(0)

    for x in 1..amount + 1:
        var m = inf
        for c in cs:
            if c <= x and best[x - c] + 1 < m: m = best[x - c] + 1
        best.append(m)

    if best[amount] >= inf: return -1

    return best[amount]

def run(line: String) -> String:
    let t = line.split(" ")
    for s in t:
        if s.length() == 0: return BAD

    let cmd = t[0]
    if cmd == "lcs" and t.length() == 3:
        return f"{lcs(t[1].to_bytes(), t[2].to_bytes())}"
    if cmd == "edit" and t.length() == 3:
        return f"{edit(t[1].to_bytes(), t[2].to_bytes())}"

    if cmd == "knap" and t.length() >= 2:
        let cap = value(t[1])
        if cap < 0: return BAD

        var ws = List[Int]()
        var vs = List[Int]()

        for k in 2..t.length():
            let parts = t[k].split(":")
            if parts.length() != 2: return BAD

            let w = value(parts[0])
            let v = value(parts[1])
            if w < 1 or v < 0: return BAD

            ws.append(w)
            vs.append(v)

        return f"{knap(cap, ws, vs)}"

    if cmd == "coins" and t.length() >= 3:
        let amount = value(t[1])
        if amount < 0: return BAD

        var cs = List[Int]()

        for k in 2..t.length():
            let c = value(t[k])
            if c < 1: return BAD

            cs.append(c)

        let n = coins(amount, cs)
        if n < 0: return "impossible"

        return f"{n}"

    return BAD

export def main() -> Int:
    var out = stdout()

    for line in read_lines(stdin()).get():
        if is_blank(line): continue

        out.write(f"{run(line)}\n").get()

    return 0
