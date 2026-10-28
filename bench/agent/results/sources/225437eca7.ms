import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import Bytes from "@std/bytes.ms"
import range from "@std/collections.ms"

let BAD = "error: bad command"

# Returns the value of a 1 to 6 digit decimal token, or -1 when it is malformed.
fn number(text: String) Int:
    if text.byte_length() < 1 or text.byte_length() > 6: return -1

    var n = 0

    for c in text.scalar_values():
        if c < 48 or c > 57: return -1

        n = n * 10 + c - 48

    return n

fn zeros(n: Int) List[Int]:
    var xs = [0]
    for i in range(1, n): xs.append(0)
    return xs

fn lcs(a: Bytes, b: Bytes) Int:
    var prev = zeros(b.length() + 1)
    var cur = zeros(b.length() + 1)

    for i in range(1, a.length() + 1):
        for j in range(1, b.length() + 1):
            if a.get(i - 1) == b.get(j - 1):
                cur[j] = prev[j - 1] + 1
            else:
                cur[j] = cur[j - 1]
                if prev[j] > cur[j]: cur[j] = prev[j]

        prev = cur.clone()

    return prev[b.length()]

fn edit(a: Bytes, b: Bytes) Int:
    var prev = zeros(b.length() + 1)
    for j in range(0, b.length() + 1): prev[j] = j

    var cur = zeros(b.length() + 1)

    for i in range(1, a.length() + 1):
        cur[0] = i

        for j in range(1, b.length() + 1):
            var cost = 1
            if a.get(i - 1) == b.get(j - 1): cost = 0

            var best = prev[j - 1] + cost
            if prev[j] + 1 < best: best = prev[j] + 1
            if cur[j - 1] + 1 < best: best = cur[j - 1] + 1
            cur[j] = best

        prev = cur.clone()

    return prev[b.length()]

fn knap(cap: Int, ws: List[Int], vs: List[Int]) Int:
    var total = 0
    for w in ws: total += w

    var limit = cap
    if total < cap: limit = total

    var best = zeros(limit + 1)

    for k in range(0, ws.length()):
        let w = ws[k]
        if w > limit: continue

        for step in range(0, limit - w + 1):
            let c = limit - step
            if best[c - w] + vs[k] > best[c]: best[c] = best[c - w] + vs[k]

    return best[limit]

fn coins(amount: Int, denoms: List[Int]) Int:
    let inf = amount + 1
    var dp = [0]

    for a in range(1, amount + 1):
        var fewest = inf
        for c in denoms:
            if c <= a and dp[a - c] + 1 < fewest: fewest = dp[a - c] + 1
        dp.append(fewest)

    return dp[amount]

fn answer(line: String) String:
    let tokens = line.split(" ")
    let command = tokens[0]

    if command == "lcs" or command == "edit":
        if tokens.length() != 3 or tokens[1].is_empty() or tokens[2].is_empty(): return BAD

        let a = tokens[1].to_bytes()
        let b = tokens[2].to_bytes()
        if command == "lcs": return "{lcs(a, b)}"

        return "{edit(a, b)}"

    if command == "knap":
        if tokens.length() < 2: return BAD

        let cap = number(tokens[1])
        if cap < 0: return BAD

        var ws: List[Int] = []
        var vs: List[Int] = []

        for k in range(2, tokens.length()):
            let item = tokens[k].split(":")
            if item.length() != 2: return BAD

            let w = number(item[0])
            let v = number(item[1])
            if w < 1 or v < 0: return BAD

            ws.append(w)
            vs.append(v)

        return "{knap(cap, ws, vs)}"

    if command == "coins":
        if tokens.length() < 3: return BAD

        let amount = number(tokens[1])
        if amount < 0: return BAD

        var denoms: List[Int] = []

        for k in range(2, tokens.length()):
            let c = number(tokens[k])
            if c < 1: return BAD

            denoms.append(c)

        let fewest = coins(amount, denoms)
        if fewest > amount: return "impossible"

        return "{fewest}"

    return BAD

fn is_blank(line: String) Bool:
    for c in line.scalar_values():
        if c != 32: return false
    return true

export fn main() Int:
    for line in read_lines(stdin()).get():
        if is_blank(line): continue

        stdout().write(answer(line) + "\n").get()

    return 0
