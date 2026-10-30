import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"
import range from "@std/collections.ms"
import SortedMap from "@std/sorted.ms"

# A valid record: its category and its amount as a string of cents (digits only, no leading zeros).
type Record:
    category: String
    cents: String

fn is_digits(text: String) Bool:
    if text.length() == 0:
        return false

    for i in range(0, text.length()):
        let code = text.scalar_at(i)
        if code < 48 or code > 57:
            return false

    return true

# Converts "12", "12.5" or "0.07" into cents as digits; none when the text is not a valid amount.
fn amount_cents(text: String) Optional[String]:
    let parts = text.split(".")
    if parts.length() > 2:
        return none

    let whole = parts[0]
    var fraction = ""

    if parts.length() == 2:
        fraction = parts[1]
        if fraction.length() < 1 or fraction.length() > 2:
            return none

    if not is_digits(whole):
        return none
    if parts.length() == 2 and not is_digits(fraction):
        return none

    if fraction.length() == 1:
        fraction = fraction + "0"
    if fraction.length() == 0:
        fraction = "00"
    return some(strip_zeros(whole + fraction))

fn strip_zeros(digits: String) String:
    var start = 0
    while start < digits.length() - 1 and digits.scalar_at(start) == 48:
        start += 1
    return digits.slice_scalars(start, digits.length()).get()

# Splits one line into its two fields, honouring double quotes around the category.
fn parse_line(line: String) Optional[Record]:
    var category = ""
    var amount = ""

    if line.starts_with("\""):
        let quoted = line.split("\"")
        if quoted.length() != 3 or not quoted[2].starts_with(","):
            return none

        category = quoted[1]
        amount = quoted[2].slice_scalars(1, quoted[2].length()).get()
    else:
        let fields = line.split(",")
        if fields.length() != 2:
            return none

        category = fields[0]
        amount = fields[1]

    if category.length() == 0:
        return none

    if let cents = amount_cents(amount):
        return some(Record(category: category, cents: cents))
    else:
        return none

fn add_digits(a: String, b: String) String:
    var i = a.length() - 1
    var j = b.length() - 1
    var carry = 0
    var out = ""

    while i >= 0 or j >= 0 or carry > 0:
        var sum = carry

        if i >= 0:
            sum += a.scalar_at(i) - 48
            i -= 1

        if j >= 0:
            sum += b.scalar_at(j) - 48
            j -= 1

        out = "{sum % 10}" + out
        carry = sum / 10

    return strip_zeros(out)

# Formats cents digits as a plain decimal with exactly two fraction digits.
fn format_total(cents: String) String:
    var padded = cents
    while padded.length() < 3:
        padded = "0" + padded

    let n = padded.length()
    return (
        padded.slice_scalars(0, n - 2).get()
        + "."
        + padded.slice_scalars(n - 2, n).get()
    )

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var totals = SortedMap[String, String]()
    var skipped = 0

    for line in lines:
        if line.trim().length() == 0:
            continue

        if let record = parse_line(line):
            totals.add(
                record.category,
                add_digits(
                    totals.get(record.category).get("0"), record.cents
                )
            )
        else:
            skipped += 1

    var out = ""
    for category in totals.keys():
        out += "{category}: {format_total(totals.get(category).get("0"))}\n"
    if skipped > 0:
        out += "skipped: {skipped}\n"
    stdout().write(out).get()
    return 0
