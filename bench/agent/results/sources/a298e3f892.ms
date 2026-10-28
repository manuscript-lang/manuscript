import {read_line, stdin, stdout} from "@std/io.ms"
import {BigInt, parse} from "@std/bigint.ms"
import StringBuilder from "@std/string.ms"

type Entry:
    category: String
    cents: BigInt

fn is_digits(text: String) Bool:
    if text.is_empty():
        return false

    for c in text.chars():
        if not "0123456789".contains(c):
            return false
    return true

# Returns the amount in cents, so "12.5" becomes 1250 and "0.07" becomes 7.
fn parse_amount(text: String) Optional[BigInt]:
    let parts = text.split(".")
    if parts.length() > 2:
        return none

    let whole = parts[0]
    if not is_digits(whole):
        return none

    var fraction = "00"

    if parts.length() == 2:
        let digits = parts[1]
        if digits.length() == 0 or digits.length() > 2 or not is_digits(digits):
            return none

        if digits.length() == 1:
            fraction = digits + "0"
        else:
            fraction = digits

    return some(parse(whole + fraction, 10).get())

# A quoted category may contain commas but no quotes, so splitting on quotes isolates it.
fn parse_line(line: String) Optional[Entry]:
    var category = ""
    var amount = ""

    if line.starts_with("\""):
        let parts = line.split("\"")
        if parts.length() != 3 or not parts[2].starts_with(","):
            return none

        category = parts[1]
        amount = parts[2].slice(1, parts[2].length()).get()
    else:
        let parts = line.split(",")
        if parts.length() != 2:
            return none

        category = parts[0]
        amount = parts[1]

    if category.is_empty():
        return none
    if let cents = parse_amount(amount):
        return some(Entry(category: category, cents: cents))

    return none

fn format_cents(cents: BigInt) String:
    let digits = "00" + cents.to_string_radix(10)
    let split_at = digits.length() - 2
    var whole = digits.slice(0, split_at).get()
    while whole.length() > 1 and whole.starts_with("0"):
        whole = whole.slice(1, whole.length()).get()
    return whole + "." + digits.slice(split_at, digits.length()).get()

fn compare_text(left: String, right: String) Int:
    return left.compare(right)

export fn main() Int:
    var totals = Map[String, BigInt]()
    var skipped = 0
    let input = stdin()
    var done = false

    while not done:
        if let line = read_line(input).get():
            if line.trim().is_empty():
                continue

            if let entry = parse_line(line):
                if let total = totals.get(entry.category):
                    totals.add(entry.category, total.add(entry.cents))
                else:
                    totals.add(entry.category, entry.cents)
            else:
                skipped += 1
        else:
            done = true

    var out = StringBuilder()
    for category in totals.keys().sorted(compare_text):
        out.append(category + ": " + format_cents(totals.get(category).get()) + "\n")
    if skipped > 0:
        out.append("skipped: {skipped}\n")
    stdout().write(out.build()).get()
    stdout().flush().get()
    return 0
