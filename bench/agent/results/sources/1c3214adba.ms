import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

// amount in cents, or none
fn parse_amount(s: String) Int?:
	parts := s.split(".")
	if parts.length() == 1:
		if not is_digits(parts.get(0, "")): return none
		return (parts.get(0, "").parse_int().get(0)) * 100
	if parts.length() != 2: return none
	whole := parts.get(0, "")
	frac := parts.get(1, "")
	if not is_digits(whole) or not is_digits(frac): return none
	if frac.length() > 2: return none
	w := whole.parse_int().get(0)
	f := frac.parse_int().get(0)
	if frac.length() == 1: return w * 100 + f * 10
	return w * 100 + f

fn sub(s: String, a: Int, b: Int) String:
	if x := s.slice(a, b): return x.clone()
	return ""

type Rec:
	cat: String
	cents: Int

fn parse_line(line: String) Rec?:
	var cat = ""
	var amt = ""
	n := line.length()
	if line.starts_with("\""):
		rest := sub(line, 1, n)
		if idx := rest.find_char(fn c: c == "\""):
			cat = sub(rest, 0, idx)
			after := sub(rest, idx + 1, rest.length())
			if not after.starts_with(","): return none
			amt = sub(after, 1, after.length())
		else:
			return none
	else:
		parts := line.split(",")
		if parts.length() != 2: return none
		cat = parts.get(0, "").clone()
		amt = parts.get(1, "").clone()
	if cat.length() == 0: return none
	if c := parse_amount(amt):
		return Rec(cat, c)
	return none

fn two(n: Int) String:
	if n < 10: return "0{n}"
	return "{n}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var totals = Map[String, Int]()
	var skipped = 0
	for raw in lines(stdin()):
		line := raw.trim_end_chars("\r")
		if line.length() == 0: continue
		if r := parse_line(line):
			totals[r.cat.clone()] = totals.get_or(r.cat, 0) + r.cents
		else:
			skipped += 1
	keys := totals.keys().sorted()
	for k in keys:
		t := totals.get_or(k, 0)
		print("{k}: {t / 100}.{two(t % 100)}")
	if skipped > 0:
		print("skipped: {skipped}")
