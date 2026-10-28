import Bytes from "@std/bytes.ms"
import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Parses 1 to 6 unsigned decimal digits; anything else is malformed.
fn parse_num(text: String) Optional[Int]:
    if text.length() < 1 or text.length() > 6: return none
    if text.get(0) == "-" or text.get(0) == "+": return none

    return text.parse_int()

fn zeros(n: Int) List[Int]:
    var xs = List[Int](reserve: n)
    for i in 0..n:
        xs.append(0)
    return xs

fn lcs(a: Bytes, b: Bytes) Int:
    let m = b.length()
    var prev = zeros(m + 1)

    for i in 0..a.length():
        var cur = zeros(m + 1)

        for j in 0..m:
            if a.get(i) == b.get(j):
                cur[j + 1] = prev[j] + 1
            else:
                cur[j + 1] = prev[j + 1].max(cur[j])

        prev = cur

    return prev[m]

fn edit(a: Bytes, b: Bytes) Int:
    let m = b.length()
    var prev = zeros(m + 1)
    for j in 0..m + 1:
        prev[j] = j

    for i in 0..a.length():
        var cur = zeros(m + 1)
        cur[0] = i + 1

        for j in 0..m:
            let cost = if a.get(i) == b.get(j): 0 else: 1

            cur[j + 1] = (prev[j] + cost).min(prev[j + 1] + 1).min(cur[j] + 1)

        prev = cur

    return prev[m]

# 0/1 knapsack. dp[j] is the best value within weight j, so the table is monotone and dp[c] is the answer.
fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
    var total = 0
    for w in ws:
        total += w

    let c = cap.min(total)
    var dp = zeros(c + 1)

    for k in 0..ws.length():
        let w = ws[k]

        if w <= c:
            for t in 0..c - w + 1:
                let j = c - t
                dp[j] = dp[j].max(dp[j - w] + vs[k])

    return dp[c]

# Returns the fewest coins, or -1 when the amount cannot be made.
fn coins(amount: Int, cs: List[Int]) Int:
    let inf = amount + 1
    var dp = zeros(amount + 1)

    for a in 1..amount + 1:
        var best = inf
        for c in cs:
            if c <= a:
                best = best.min(dp[a - c] + 1)
        dp[a] = best

    if dp[amount] > amount: return -1

    return dp[amount]

# Returns the answer, or -1 for a malformed command.
fn knap_cmd(parts: List[String]) Int:
    let cap = parse_num(parts[1]).get(-1)
    if cap < 0: return -1

    var ws = List[Int]()
    var vs = List[Int]()

    for i in 2..parts.length():
        let pair = parts[i].split(":")
        if pair.length() != 2: return -1

        let w = parse_num(pair[0]).get(-1)
        let v = parse_num(pair[1]).get(-1)
        if w < 1 or v < 0: return -1

        ws.append(w)
        vs.append(v)

    return knap(cap, ws, vs)

# Returns the fewest coins (or -1 when impossible), or -2 for a malformed command.
fn coins_cmd(parts: List[String]) Int:
    let amount = parse_num(parts[1]).get(-1)
    if amount < 0: return -2

    var cs = List[Int]()

    for i in 2..parts.length():
        let c = parse_num(parts[i]).get(-1)
        if c < 1: return -2

        cs.append(c)

    return coins(amount, cs)

fn solve(parts: List[String]) String:
    let cmd = parts[0]
    let n = parts.length()
    if cmd == "lcs" and n == 3 and parts[1].length() > 0 and parts[2].length() > 0:
        return "{lcs(parts[1].to_bytes(), parts[2].to_bytes())}"
    if cmd == "edit" and n == 3 and parts[1].length() > 0 and parts[2].length() > 0:
        return "{edit(parts[1].to_bytes(), parts[2].to_bytes())}"

    if cmd == "knap" and n >= 2:
        let best = knap_cmd(parts)
        if best >= 0: return "{best}"

    if cmd == "coins" and n >= 3:
        let fewest = coins_cmd(parts)
        if fewest == -1: return "impossible"
        if fewest >= 0: return "{fewest}"

    return "error: bad command"

# A line is blank when every space-separated part is empty.
fn is_blank(parts: List[String]) Bool:
    for p in parts:
        if p.length() > 0: return false
    return true

export fn main() Int:
    var out = stdout()

    for line in read_lines(stdin()).get():
        let parts = line.split(" ")
        if not is_blank(parts):
            out.write("{solve(parts)}\n").get()

    return 0
