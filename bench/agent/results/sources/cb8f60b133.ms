import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import SortedMap from "@std/sorted.ms"

type Record:
    category: String
    amount: String

# True for one ASCII digit.
fn is_digit(c: String) Bool:
    return c.length() == 1 and "0123456789".contains(c)

# Amount grammar: digits, optionally `.` followed by one or two digits.
fn valid_amount(s: String) Bool:
    let n = s.length()
    var i = 0
    while i < n and is_digit(s.get(i)):
        i += 1
    if i == 0:
        return false
    if i == n:
        return true
    if s.get(i) != ".":
        return false

    let frac = n - i - 1
    if frac < 1 or frac > 2:
        return false

    for j in i + 1..n:
        if not is_digit(s.get(j)):
            return false
    return true

# Splits one line into category and amount; none when the line is invalid.
fn parse_line(line: String) Record?:
    var category = ""
    var amount = ""

    if line.get(0) == "\"":
        let rest_after_quote = line.drop(1)

        if let close = rest_after_quote.index_of("\""):
            category = rest_after_quote.take(close)

            let tail = rest_after_quote.drop(close + 1)
            if not tail.starts_with(","):
                return none

            amount = tail.drop(1)
        else:
            return none
    else:
        if let comma = line.index_of(","):
            category = line.take(comma)
            amount = line.drop(comma + 1)
        else:
            return none

    if category.is_empty() or not valid_amount(amount):
        return none

    return Record(category: category, amount: amount)

# Converts a valid amount to a digit string of whole cents, without leading zeros.
fn to_cents(amount: String) String:
    var whole = amount.clone()
    var frac = "00"

    if let dot = amount.index_of("."):
        whole = amount.take(dot)
        frac = amount.drop(dot + 1).pad_end(2, "0")

    var digits = whole.concat(frac)
    while digits.length() > 1 and digits.get(0) == "0":
        digits = digits.drop(1)
    return digits

# Exact addition of two non-negative digit strings.
fn add_digits(a: String, b: String) String:
    var i = a.length() - 1
    var j = b.length() - 1
    var carry = 0
    var out = ""

    while i >= 0 or j >= 0 or carry > 0:
        var d = carry

        if i >= 0:
            d += a.get(i).parse_int().get(0)
            i -= 1

        if j >= 0:
            d += b.get(j).parse_int().get(0)
            j -= 1

        out = "{d % 10}".concat(out)
        carry = d / 10

    return out

# Renders a cents digit string as `whole.cc`.
fn format_cents(cents: String) String:
    let s = cents.pad_start(3, "0")
    let cut = s.length() - 2
    return "{s.take(cut)}.{s.drop(cut)}"

export fn main() Int:
    var skipped = 0
    var totals = SortedMap[String, String]()

    if let lines = read_lines(stdin()):
        for line in lines:
            if line.trim().is_empty():
                continue

            if let rec = parse_line(line):
                let cents = to_cents(rec.amount)

                if let current = totals.get(rec.category):
                    totals.add(rec.category, add_digits(current, cents))
                else:
                    totals.add(rec.category, cents)
            else:
                skipped += 1

    var out = List[String]()
    for entry in totals.entries():
        out.append("{entry.key}: {format_cents(entry.value)}\n")
    if skipped > 0:
        out.append("skipped: {skipped}\n")
    stdout().write(out.join("")).get()
    return 0
