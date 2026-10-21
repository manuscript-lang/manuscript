import {read_line, stdin, stdout} from "@std/io.ms"
import {range} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"

# Returns the value of a 1 to 6 digit decimal, or -1 when the text is not one.
fn parse_num(text: String) Int:
    let digits = text.to_bytes()
    if digits.length() == 0 or digits.length() > 6:
        return -1

    var value = 0

    for i in range(0, digits.length()):
        let d = digits.get(i) - 48
        if d < 0 or d > 9:
            return -1

        value = value * 10 + d

    return value

fn non_empty(text: String) Bool:
    return text.length() > 0

fn is_blank(line: String) Bool:
    let bytes = line.to_bytes()
    for i in range(0, bytes.length()):
        if bytes.get(i) != 32:
            return false
    return true

fn zeros(count: Int) List[Int]:
    var row = [0]
    for i in range(1, count):
        row.append(0)
    return row

fn max2(a: Int, b: Int) Int:
    if a > b:
        return a

    return b

fn min3(a: Int, b: Int, c: Int) Int:
    return min2(min2(a, b), c)

fn min2(a: Int, b: Int) Int:
    if a < b:
        return a

    return b

fn lcs_length(a: Bytes, b: Bytes) Int:
    let n = b.length()
    var prev = zeros(n + 1)

    for i in range(0, a.length()):
        var cur = zeros(n + 1)

        for j in range(0, n):
            if a.get(i) == b.get(j):
                cur.set(j + 1, prev.get(j) + 1)
            else:
                cur.set(j + 1, max2(prev.get(j + 1), cur.get(j)))

        prev = cur

    return prev.get(n)

fn edit_distance(a: Bytes, b: Bytes) Int:
    let n = b.length()
    var prev = zeros(n + 1)
    for j in range(0, n + 1):
        prev.set(j, j)

    for i in range(0, a.length()):
        var cur = zeros(n + 1)
        cur.set(0, i + 1)

        for j in range(0, n):
            var cost = 1
            if a.get(i) == b.get(j):
                cost = 0
            cur.set(
                j + 1,
                min3(
                    prev.get(j + 1) + 1,
                    cur.get(j) + 1,
                    prev.get(j) + cost
                )
            )

        prev = cur

    return prev.get(n)

# An item is a `w:v` token with a weight of at least 1 and a value of at least 0.
fn item_valid(token: String) Bool:
    let parts = token.split(":")
    if parts.length() != 2:
        return false

    return parse_num(parts.get(0)) >= 1 and parse_num(parts.get(1)) >= 0

fn knapsack(tokens: List[String]) String:
    let cap = parse_num(tokens.get(1))
    if cap < 0:
        return "error: bad command"

    for i in range(2, tokens.length()):
        if not item_valid(tokens.get(i)):
            return "error: bad command"
    var best = zeros(cap + 1)

    for i in range(2, tokens.length()):
        let parts = tokens.get(i).split(":")
        let w = parse_num(parts.get(0))
        let v = parse_num(parts.get(1))

        if w <= cap:
            for k in range(0, cap - w + 1):
                let c = cap - k
                best.set(c, max2(best.get(c), best.get(c - w) + v))

    return "{best.get(cap)}"

fn coin_change(tokens: List[String]) String:
    let amount = parse_num(tokens.get(1))
    if amount < 0:
        return "error: bad command"

    var coins: List[Int] = []

    for i in range(2, tokens.length()):
        let c = parse_num(tokens.get(i))
        if c < 1:
            return "error: bad command"

        coins.append(c)

    let unreachable = amount + 1
    var fewest = zeros(amount + 1)

    for x in range(1, amount + 1):
        var best = unreachable
        for c in coins:
            if c <= x and fewest.get(x - c) + 1 < best:
                best = fewest.get(x - c) + 1
        fewest.set(x, best)

    if fewest.get(amount) >= unreachable:
        return "impossible"

    return "{fewest.get(amount)}"

fn answer(line: String) String:
    let tokens = line.split(" ")
    let cmd = tokens.get(0)
    if (
        cmd == "lcs"
        and tokens.length() == 3
        and non_empty(tokens.get(1))
        and non_empty(tokens.get(2))
    ):
        return "{lcs_length(tokens.get(1).to_bytes(), tokens.get(2).to_bytes())}"
    if (
        cmd == "edit"
        and tokens.length() == 3
        and non_empty(tokens.get(1))
        and non_empty(tokens.get(2))
    ):
        return "{edit_distance(tokens.get(1).to_bytes(), tokens.get(2).to_bytes())}"
    if cmd == "knap" and tokens.length() >= 2:
        return knapsack(tokens)
    if cmd == "coins" and tokens.length() >= 3:
        return coin_change(tokens)

    return "error: bad command"

export fn main() Int:
    let input = stdin()
    let output = stdout()
    var reading = true

    while reading:
        if let line = read_line(input).get():
            if not is_blank(line):
                output.write("{answer(line)}\n").get()
        else:
            reading = false

    output.flush().get()
    return 0
