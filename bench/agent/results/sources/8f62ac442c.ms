import stdin, stdout from "@std/io.ms"
import max, min from "@std/math.ms"
import read_lines from "@std/streams.ms"

type Item:
    weight: Int
    value: Int

# Parses a decimal number of 1 to 6 digits that is at least `floor`.
fn parse_num(text: String, floor: Int) Optional[Int]:
    if text.length() < 1 or text.length() > 6: return none

    for c in text.chars():
        if not "0123456789".contains(c): return none
    if let num = text.parse_int():
        if num >= floor: return some(num)
    return none

fn parse_nums(tokens: List[String], first: Int, floor: Int) Optional[List[Int]]:
    var nums = List[Int]()

    for i in first..tokens.length():
        if let num = parse_num(tokens.get(i), floor):
            nums.append(num)
        else:
            return none

    return some(nums)

fn parse_item(token: String) Optional[Item]:
    let parts = token.split(":")
    if parts.length() != 2: return none

    if let weight = parse_num(parts.get(0), 1):
        if let value = parse_num(parts.get(1), 0):
            return some(Item(weight: weight, value: value))
    return none

fn parse_items(tokens: List[String]) Optional[List[Item]]:
    var items = List[Item]()

    for i in 2..tokens.length():
        if let item = parse_item(tokens.get(i)):
            items.append(item)
        else:
            return none

    return some(items)

fn lcs(a: String, b: String) Int:
    let x = a.to_bytes()
    let y = b.to_bytes()
    var prev = List[Int]()
    for j in 0..(y.length() + 1):
        prev.append(0)

    for i in 0..x.length():
        var cur = List[Int]()
        cur.append(0)

        for j in 0..y.length():
            if x.get(i) == y.get(j):
                cur.append(prev.get(j) + 1)
            else:
                cur.append(max(prev.get(j + 1), cur.get(j)))

        prev = cur

    return prev.get(y.length())

fn edit(a: String, b: String) Int:
    let x = a.to_bytes()
    let y = b.to_bytes()
    var prev = List[Int]()
    for j in 0..(y.length() + 1):
        prev.append(j)

    for i in 0..x.length():
        var cur = List[Int]()
        cur.append(i + 1)

        for j in 0..y.length():
            let cost = if x.get(i) == y.get(j): 0 else: 1

            cur.append(
                min(
                    min(prev.get(j) + cost, prev.get(j + 1) + 1), cur.get(j) + 1
                )
            )

        prev = cur

    return prev.get(y.length())

fn knap(cap: Int, items: List[Item]) Int:
    var best = List[Int]()
    for c in 0..(cap + 1):
        best.append(0)

    for item in items:
        var updated = best.clone()
        for c in item.weight..(cap + 1):
            updated[c] = max(best.get(c), best.get(c - item.weight) + item.value)
        best = updated

    return best.get(cap)

# Fewest coins summing to `amount`, or -1 when no combination works.
fn fewest_coins(amount: Int, denoms: List[Int]) Int:
    var best = List[Int]()
    best.append(0)

    for a in 1..(amount + 1):
        var fewest = -1

        for c in denoms:
            if c <= a and best.get(a - c) >= 0:
                let k = best.get(a - c) + 1
                if fewest < 0 or k < fewest: fewest = k

        best.append(fewest)

    return best.get(amount)

fn run(line: String) String:
    let tokens = line.split(" ")
    let cmd = tokens.get(0)
    if cmd == "lcs" and tokens.length() == 3:
        if not tokens.get(1).is_empty() and not tokens.get(2).is_empty():
            return "{lcs(tokens.get(1), tokens.get(2))}"
    if cmd == "edit" and tokens.length() == 3:
        if not tokens.get(1).is_empty() and not tokens.get(2).is_empty():
            return "{edit(tokens.get(1), tokens.get(2))}"
    if cmd == "knap" and tokens.length() >= 2:
        if let cap = parse_num(tokens.get(1), 0):
            if let items = parse_items(tokens):
                return "{knap(cap, items)}"

    if cmd == "coins" and tokens.length() >= 3:
        if let amount = parse_num(tokens.get(1), 0):
            if let denoms = parse_nums(tokens, 2, 1):
                let fewest = fewest_coins(amount, denoms)

                return if fewest < 0: "impossible" else: "{fewest}"

    return "error: bad command"

fn is_blank(line: String) Bool:
    return line.chars().all(fn c: c == " ")

export fn main() Int:
    var out = stdout()
    for line in read_lines(stdin()).get():
        if not is_blank(line):
            out.write("{run(line)}\n").get()
    return 0
