import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Row:
    category: String
    cents: String

fn is_digits(text: String) Bool:
    if text.is_empty(): return false

    for c in text.scalar_values():
        if c < 48 or c > 57: return false
    return true

# Converts an amount such as `12`, `12.5` or `0.07` to a string of hundredths.
fn amount_cents(text: String) Optional[String]:
    let parts = text.split(".")

    if parts.length() == 1:
        if is_digits(text): return some(text + "00")

        return none

    if parts.length() != 2: return none

    let whole = parts[0]
    let frac = parts[1]
    if not is_digits(whole) or not is_digits(frac) or frac.scalar_length() > 2: return none
    if frac.scalar_length() == 1: return some(whole + frac + "0")

    return some(whole + frac)

# Returns the record in `line` as its category and amount, or none when the line is invalid.
fn parse_row(line: String) Optional[Row]:
    if line.starts_with("\""):
        let rest = line.slice_scalars(1, line.scalar_length()).get()

        if let close = rest.index_of("\""):
            let category = rest.slice_scalars(0, close).get()
            let tail = rest.slice_scalars(close + 1, rest.scalar_length()).get()
            if not tail.starts_with(",") or category.is_empty(): return none
            if let cents = amount_cents(
                tail.slice_scalars(1, tail.scalar_length()).get()
            ):
                return some(Row(category: category, cents: cents))

        return none

    let parts = line.split(",")
    if parts.length() != 2 or parts[0].is_empty(): return none
    if let cents = amount_cents(parts[1]):
        return some(Row(category: parts[0], cents: cents))

    return none

fn digit_at(text: String, from_end: Int) Int:
    if from_end > text.scalar_length(): return 0

    return text.scalar_at(-from_end) - 48

# Adds two non-negative decimal digit strings exactly.
fn add_digits(a: String, b: String) String:
    var result = ""
    var carry = 0
    var i = 1
    var n = a.scalar_length()
    if b.scalar_length() > n: n = b.scalar_length()

    while i <= n or carry > 0:
        let d = digit_at(a, i) + digit_at(b, i) + carry
        result = "{d % 10}" + result
        carry = d / 10
        i += 1

    return result

fn strip_zeros(text: String) String:
    var out = text
    while out.scalar_length() > 1 and out.starts_with("0"):
        out = out.slice_scalars(1, out.scalar_length()).get()
    return out

# Formats a hundredths string as a plain decimal with exactly two fractional digits.
fn money(cents: String) String:
    let padded = "000" + cents
    let n = padded.scalar_length()
    let whole = strip_zeros(padded.slice_scalars(0, n - 2).get())
    return whole + "." + padded.slice_scalars(n - 2, n).get()

export fn main() Int:
    var totals = Map[String, String]()
    var skipped = 0

    for line in read_lines(stdin()).get():
        if line.trim().is_empty(): continue

        if let row = parse_row(line):
            totals.add(
                row.category, add_digits(totals.get_or(row.category, "0"), row.cents)
            )
        else:
            skipped += 1

    var out = stdout()
    for category in totals.keys().sorted(fn a, b: a.compare(b)):
        out.write(category + ": " + money(totals.get_or(category, "0")) + "\n").get()
    if skipped > 0:
        out.write("skipped: {skipped}\n").get()
    return 0
