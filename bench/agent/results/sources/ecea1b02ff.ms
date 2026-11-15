import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn parse_cents(s: String) Int?:
	parts := s.split(".")
	if parts.length() > 2: return none
	whole := parts.get(0, "")
	if not is_digits(whole): return none
	var frac = 0
	if parts.length() == 2:
		f := parts.get(1, "")
		if not is_digits(f) or f.length() > 2: return none
		frac = (if f.length() == 1: f + "0" else: f).parse_int().get(0)
	w := whole.parse_int()
	if w.is_none(): return none
	return w.get(0) * 100 + frac

type Rec:
	cat: String
	cents: Int

fn parse_line(line: String) Rec?:
	var cat = ""
	var amt = ""
	if line.starts_with("\""):
		rest := line.slice(1, line.length()).get("")
		close := rest.index_of("\"")
		if close.is_none(): return none
		c := close.get(0)
		cat = rest.slice(0, c).get("")
		after := rest.slice(c + 1, rest.length()).get("")
		if not after.starts_with(","): return none
		amt = after.slice(1, after.length()).get("")
	else:
		parts := line.split(",")
		if parts.length() != 2: return none
		cat = parts.get(0, "")
		amt = parts.get(1, "")
	if cat.length() == 0: return none
	cents := parse_cents(amt)
	if cents.is_none(): return none
	return Rec(cat, cents.get(0))

// ms: allow_effect std.console.write
fn main() Unit!:
	var totals = Map[String, Int]()
	var skipped = 0
	for line in lines(stdin()):
		if line.length() == 0: continue
		r := parse_line(line)
		if p := r:
			prev := totals.get_or(p.cat, 0)
			totals[p.cat.clone()] = prev + p.cents
		else:
			skipped += 1
	keys := totals.keys().sorted()
	for k in keys:
		t := totals.get_or(k, 0)
		frac := (t % 100).to_string().pad_start(2, "0")
		print("{k}: {t / 100}.{frac}")
	if skipped > 0:
		print("skipped: {skipped}")
