import {stdout, stdin} from "@std/io.ms"
import read_lines from "@std/streams.ms"

# Parses `digits[.d]` or `digits[.dd]` into cents; none if the text does not match.
fn parse_amount(text: String) Optional[Int]:
    let parts = text.split(".")
    if parts.length() > 2: return none
    let whole = parts[0]
    if whole.length() == 0: return none
    var cents = 0
    for ch in whole.chars():
        if not "0123456789".contains(ch): return none
        cents = cents * 10 + ch.parse_int().get(0)
    cents = cents * 100
    if parts.length() == 2:
        let frac = parts[1]
        if frac.length() < 1 or frac.length() > 2: return none
        var scale = 10
        for ch in frac.chars():
            if not "0123456789".contains(ch): return none
            cents += ch.parse_int().get(0) * scale
            scale = 1
    return cents

type Record:
    category: String
    cents: Int

# Returns the category and cents of a record line, or none if the line is invalid.
fn parse_record(line: String) Optional[Record]:
    var category = ""
    var amount = ""
    if line.starts_with("\""):
        let parts = line.split("\"")
        if parts.length() != 3: return none
        category = parts[1].clone()
        let tail = parts[2].split(",")
        if tail.length() != 2 or tail[0].length() != 0: return none
        amount = tail[1].clone()
    else:
        let parts = line.split(",")
        if parts.length() != 2: return none
        category = parts[0].clone()
        amount = parts[1].clone()
    if category.length() == 0: return none
    if let cents = parse_amount(amount):
        return Record(category, cents)
    return none

fn format_cents(cents: Int) String:
    let frac = cents % 100
    let pad = if frac < 10: "0" else: ""
    return "{cents / 100}.{pad}{frac}"

export fn main() Int:
    var totals = Map[String, Int]()
    var skipped = 0
    if let lines = read_lines(stdin()):
        for line in lines:
            if line.trim().length() == 0: continue
            if let record = parse_record(line):
                let category = record.category.clone()
                totals[category.clone()] = totals.get(category.clone()).get(0) + record.cents
            else:
                skipped += 1
    var out = ""
    for category in totals.keys().sorted():
        out += "{category}: {format_cents(totals.get(category).get(0))}\n"
    if skipped > 0:
        out += "skipped: {skipped}\n"
    stdout().write(out).get()
    return 0
