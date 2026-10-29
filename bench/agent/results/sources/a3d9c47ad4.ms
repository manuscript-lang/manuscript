import {stdin, stdout} from "@std/io.ms"
import {BigInt, from_int} from "@std/math.ms"
import read_lines from "@std/streams.ms"

type Entry:
    category: String
    cents: BigInt

fn is_digits(text: String) Bool:
    return text.length() > 0 and text.chars().all(fn c: "0123456789".contains(c))

fn digits_value(text: String) BigInt:
    var total = from_int(0)
    for c in text.chars():
        total = total * from_int(10) + from_int("0123456789".index_of(c).get(0))
    return total

# Converts an amount such as `12`, `12.5` or `0.07` to exact cents.
fn amount_cents(amount: String) Optional[BigInt]:
    let parts = amount.split(".")
    if parts.length() == 1:
        if is_digits(amount):
            return some(digits_value(amount) * from_int(100))
        return none
    if parts.length() != 2 or not is_digits(parts[0]):
        return none
    let fraction = parts[1]
    if fraction.length() < 1 or fraction.length() > 2 or not is_digits(fraction):
        return none
    var padded = fraction.clone()
    if fraction.length() == 1:
        padded = fraction + "0"
    return some(digits_value(parts[0]) * from_int(100) + digits_value(padded))

# A quoted category may contain commas; an unquoted one ends at the first comma.
fn parse_line(line: String) Optional[Entry]:
    let chars = line.chars()
    var category = ""
    var start = 0
    if chars.length() > 0 and chars[0] == "\"":
        var close = 1
        while close < chars.length() and chars[close] != "\"":
            close += 1
        if close == chars.length() or close + 1 >= chars.length() or chars[close + 1] != ",":
            return none
        for i in 1..close:
            category += chars[i]
        start = close + 2
    else:
        var comma = 0
        while comma < chars.length() and chars[comma] != ",":
            comma += 1
        if comma == chars.length():
            return none
        for i in 0..comma:
            category += chars[i]
        start = comma + 1
    if category == "":
        return none
    var amount = ""
    for i in start..chars.length():
        amount += chars[i]
    if let cents = amount_cents(amount):
        return some(Entry(category: category, cents: cents))
    return none

fn format_cents(cents: BigInt) String:
    let hundred = from_int(100)
    let whole = (cents / hundred).to_string_radix(10)
    let fraction = (cents % hundred).to_int().get(0)
    if fraction < 10:
        return "{whole}.0{fraction}"
    return "{whole}.{fraction}"

export fn main() Int:
    var totals = Map[String, BigInt]()
    var skipped = 0
    for line in read_lines(stdin()).get():
        if line == "":
            continue
        if let entry = parse_line(line):
            let category = entry.category.clone()
            totals[category.clone()] = totals.get(category).get(from_int(0)) + entry.cents
        else:
            skipped += 1
    var output = ""
    var categories = totals.keys()
    categories.sort()
    for category in categories:
        output += "{category}: {format_cents(totals.get(category).get(from_int(0)))}\n"
    if skipped > 0:
        output += "skipped: {skipped}\n"
    stdout().write(output).get()
    return 0
