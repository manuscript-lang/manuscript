from "@std/io.ms" import stdin, stdout
from "@std/math.ms" import BigInt, parse
from "@std/streams.ms" import read_lines

# True when `text` is one or more ASCII digits.
def is_digits(text: String) -> Bool:
    if text.length() == 0:
        return False

    for c in text.chars():
        if c.compare("0") < 0 or c.compare("9") > 0:
            return False
    return True

# Converts a valid amount such as `12.5` into whole cents, or none when it does not match the spec.
def amount_cents(text: String) -> Optional[BigInt]:
    let parts = text.split(".")
    if parts.length() > 2 or not is_digits(parts[0]):
        return none

    var frac = ""

    if parts.length() == 2:
        frac = parts[1].clone()
        if frac.length() < 1 or frac.length() > 2 or not is_digits(frac):
            return none

    if frac.length() == 1:
        frac = frac.concat("0")
    if frac.length() == 0:
        frac = "00"
    return parse(parts[0].concat(frac), 10).get()

# Splits a line into its category and amount text, or none when the line is invalid.
def split_record(line: String) -> Optional[List[String]]:
    if line.starts_with("\""):
        # A quoted category: the only quotes allowed are the two wrapping it.
        let quoted = line.split("\"")
        if quoted.length() != 3 or quoted[1].length() == 0:
            return none

        let tail = quoted[2].split(",")
        if tail.length() != 2 or tail[0].length() != 0:
            return none

        return [quoted[1].clone(), tail[1].clone()]

    let fields = line.split(",")
    if fields.length() != 2 or fields[0].length() == 0:
        return none

    return fields

export def main() -> Int:
    let lines = read_lines(stdin()).get()
    let zero = parse("0", 10).get()
    let hundred = parse("100", 10).get()
    var totals = Map[String, BigInt]()
    var skipped = 0

    for raw in lines:
        let line = raw.slice(0, -1).get() if raw.ends_with("\r") else raw

        if line.length() == 0:
            continue

        if let fields = split_record(line):
            if let cents = amount_cents(fields[1]):
                totals.update(fields[0].clone(), zero, lambda sum: sum + cents)
                continue

        skipped += 1

    var out = List[String]()

    for category in totals.keys().sorted():
        let total = totals.get_or(category, zero)
        let frac = (total % hundred).to_string_radix(10)

        let padded = "0".concat(frac) if frac.length() < 2 else frac

        out.append(f"{category}: {(total / hundred).to_string_radix(10)}.{padded}")

    if skipped > 0:
        out.append(f"skipped: {skipped}")
    if out.length() > 0:
        stdout().write(out.join("\n").concat("\n")).get()
    return 0
