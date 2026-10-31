import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Record:
    category: String
    cents: List[Int]  # big-endian digits of the amount in hundredths

# Returns the amount as big-endian hundredths digits, or none unless it is `digits[.digits{0,2}]`.
fn parse_amount(amount: String) Optional[List[Int]]:
    let parts = amount.split(".")
    if parts.length() > 2: return none

    let whole = parts[0]

    let frac = if parts.length() == 2: parts[1].clone() else: ""

    if whole == "" or (parts.length() == 2 and frac == "") or frac.length() > 2: return none

    var frac_text = frac
    while frac_text.length() < 2:
        frac_text += "0"

    var cents = List[Int]()

    for ch in (whole + frac_text).split(""):
        if let d = ch.parse_int():
            cents.append(d)
        else:
            return none

    return cents

# Splits one line into `category,amount`; a quoted category may contain commas.
fn parse_record(line: String) Optional[Record]:
    let parts = line.split("\"")
    var category = ""
    var amount = ""

    if parts.length() > 1 and parts[0] == "":
        if parts.length() != 3: return none

        let tail = parts[2].split(",")
        if tail.length() != 2 or tail[0] != "": return none

        category = parts[1].clone()
        amount = tail[1].clone()
    else:
        let fields = line.split(",")
        if fields.length() != 2: return none

        category = fields[0].clone()
        amount = fields[1].clone()

    if category == "": return none
    if let cents = parse_amount(amount):
        return some(Record(category: category, cents: cents))

    return none

# Adds two big-endian digit lists.
fn add(a: List[Int], b: List[Int]) List[Int]:
    var i = a.length() - 1
    var j = b.length() - 1
    var carry = 0
    var out = List[Int]()

    while i >= 0 or j >= 0 or carry > 0:
        var s = carry

        if i >= 0:
            s += a[i]
            i -= 1

        if j >= 0:
            s += b[j]
            j -= 1

        out.append(s % 10)
        carry = s / 10

    out.reverse()
    return out

# Formats hundredths digits as `whole.frac` with exactly two fractional digits.
fn format_cents(cents: List[Int]) String:
    let n = if cents.length() < 3: 3 else: cents.length()

    let lead = n - cents.length()
    var text = ""

    for i in 0..n:
        if i == n - 2: text += "."

        if i < lead:
            text += "0"
        else:
            text += "{cents[i - lead]}"

    return text

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var totals = Map[String, List[Int]]()
    var skipped = 0

    for line in lines:
        if line.trim() == "": continue

        if let record = parse_record(line):
            let total = add(totals.get(record.category).get(List[Int]()), record.cents)
            totals[record.category.clone()] = total
        else:
            skipped += 1

    var out = ""
    for category in totals.keys().sorted():
        out += "{category}: {format_cents(totals[category])}\n"
    if skipped > 0:
        out += "skipped: {skipped}\n"
    stdout().write(out).get()
    return 0
