import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn digits(s: String) Bool:
	if s.length() == 0: return false
	for p in s.split(""):
		if not "0123456789".contains(p): return false
	return true

fn cents(s: String) Int?:
	parts := s.split(".")
	if parts.length() > 2: return none
	whole := parts.get(0, "")
	if not digits(whole): return none
	var frac = ""
	if parts.length() == 2:
		frac = parts.get(1, "")
		if not digits(frac) or frac.length() > 2: return none
	w := whole.parse_int().get(0)
	f := frac.pad_end(2, "0").parse_int().get(0)
	return w * 100 + f

fn tail(s: String, n: Int) String:
	return s.slice(n, s.length()).get("")

// returns category and amount text, or none when invalid
fn split_record(line: String) List[String]?:
	if line.starts_with("\""):
		rest := tail(line, 1)
		idx := rest.index_of("\"").get(-1)
		if idx < 0: return none
		cat := rest.slice(0, idx).get("")
		after := tail(rest, idx + 1)
		if not after.starts_with(","): return none
		return [cat, tail(after, 1)]
	parts := line.split(",")
	if parts.length() != 2: return none
	return [parts.get(0, ""), parts.get(1, "")]

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var totals = Map[String, Int]()
	var skipped = 0
	for line in lines(stdin()):
		if line.length() == 0: continue
		var ok_line = false
		if rec := split_record(line):
			cat := rec.get(0, "")
			if cat.length() > 0:
				if c := cents(rec.get(1, "")):
					totals[cat.clone()] = totals.get_or(cat, 0) + c
					ok_line = true
		if not ok_line: skipped += 1
	var keys = List[String]()
	for e in totals.entries():
		keys.append(e.key.clone())
	keys.sort()
	for k in keys:
		t := totals.get_or(k, 0)
		print("{k}: {t / 100}.{(t % 100).to_string().pad_start(2, "0")}")
	if skipped > 0: print("skipped: {skipped}")
