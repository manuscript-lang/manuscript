import {stdin, stdout} from "@std/io.ms"
import read_lines from "@std/streams.ms"
import range from "@std/collections.ms"
import {max, min} from "@std/math.ms"

# Sentinel for any malformed number; every valid number in the spec is at least 0.
fn bad() Int:
    return -1

fn parse_num(text: String) Int:
    if text.is_empty() or text.byte_length() > 6:
        return bad()

    for ch in text.scalar_values():
        if ch < 48 or ch > 57:
            return bad()
    return text.parse_int().get(bad())

fn is_blank(line: String) Bool:
    for ch in line.scalar_values():
        if ch != 32:
            return false
    return true

fn lcs(a: List[Int], b: List[Int]) Int:
    var prev: List[Int] = []
    for j in range(0, b.length() + 1):
        prev.append(0)

    for i in range(0, a.length()):
        var cur: List[Int] = [0]

        for j in range(0, b.length()):
            if a[i] == b[j]:
                cur.append(prev[j] + 1)
            else:
                cur.append(max(prev[j + 1], cur[j]))

        prev = cur

    return prev[b.length()]

fn edit(a: List[Int], b: List[Int]) Int:
    var prev: List[Int] = []
    for j in range(0, b.length() + 1):
        prev.append(j)

    for i in range(0, a.length()):
        var cur: List[Int] = [i + 1]

        for j in range(0, b.length()):
            var cost = 1
            if a[i] == b[j]:
                cost = 0
            cur.append(min(min(prev[j + 1] + 1, cur[j] + 1), prev[j] + cost))

        prev = cur

    return prev[b.length()]

fn knap(cap: Int, weights: List[Int], values: List[Int]) Int:
    var total = 0
    for w in weights:
        total += w

    # Capacity beyond the total weight never changes the answer.
    let limit = min(cap, total)
    var best: List[Int] = []
    for c in range(0, limit + 1):
        best.append(0)

    for k in range(0, weights.length()):
        let w = weights[k]
        let v = values[k]

        # Walk capacities downward so each item is used at most once.
        for step in range(0, limit - w + 1):
            let c = limit - step
            best[c] = max(best[c], best[c - w] + v)

    return best[limit]

fn coins(amount: Int, denominations: List[Int]) String:
    # Any real count is at most `amount`, so `amount + 1` marks unreachable sums.
    let unreachable = amount + 1
    var best: List[Int] = [0]

    for a in range(1, amount + 1):
        best.append(unreachable)
        for c in denominations:
            if c <= a and best[a - c] + 1 < best[a]:
                best[a] = best[a - c] + 1

    if best[amount] >= unreachable:
        return "impossible"

    return "{best[amount]}"

fn run(line: String) String:
    let tokens = line.split(" ")
    let name = tokens[0]

    if name == "lcs" or name == "edit":
        if tokens.length() != 3:
            return "error: bad command"

        let a = tokens[1]
        let b = tokens[2]
        if a.is_empty() or b.is_empty():
            return "error: bad command"
        if name == "lcs":
            return "{lcs(a.scalar_values(), b.scalar_values())}"

        return "{edit(a.scalar_values(), b.scalar_values())}"

    if name == "knap":
        if tokens.length() < 2:
            return "error: bad command"

        let cap = parse_num(tokens[1])
        if cap < 0:
            return "error: bad command"

        var weights: List[Int] = []
        var values: List[Int] = []

        for i in range(2, tokens.length()):
            let item = tokens[i].split(":")
            if item.length() != 2:
                return "error: bad command"

            let w = parse_num(item[0])
            let v = parse_num(item[1])
            if w < 1 or v < 0:
                return "error: bad command"

            weights.append(w)
            values.append(v)

        return "{knap(cap, weights, values)}"

    if name == "coins":
        if tokens.length() < 3:
            return "error: bad command"

        let amount = parse_num(tokens[1])
        if amount < 0:
            return "error: bad command"

        var denominations: List[Int] = []

        for i in range(2, tokens.length()):
            let c = parse_num(tokens[i])
            if c < 1:
                return "error: bad command"

            denominations.append(c)

        return coins(amount, denominations)

    return "error: bad command"

export fn main() Int:
    if let lines = read_lines(stdin()):
        var out: List[String] = []
        for line in lines:
            if not is_blank(line):
                out.append(run(line))
        if out.length() > 0:
            stdout().write(out.join("\n") + "\n").get()

    return 0
