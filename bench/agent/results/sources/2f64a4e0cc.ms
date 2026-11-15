import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if c < "0" or c > "9": return false
	return true

// returns cents or -1
fn cents(s: String) Int:
	parts := s.split(".")
	if parts.length() == 1:
		if not digits(parts.get(0, "")): return -1
		return parts.get(0, "").parse_int().get(-1) * 100
	if parts.length() != 2: return -1
	w := parts.get(0, "")
	f := parts.get(1, "")
	if not digits(w) or not digits(f) or f.length() > 2: return -1
	fv := f.parse_int().get(-1)
	if f.length() == 1: return w.parse_int().get(-1) * 100 + fv * 10
	return w.parse_int().get(-1) * 100 + fv

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	var totals = Map[String, Int]()
	var bad = 0
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		var cat = ""
		var amt = ""
		var ok = true
		if line.starts_with("\""):
			parts := line.split("\"")
			if parts.length() != 3: ok = false
			else:
				rest := parts.get(2, "")
				if not rest.starts_with(","): ok = false
				else:
					cat = parts.get(1, "")
					amt = rest.slice(1, rest.length()).get("")
		else:
			parts := line.split(",")
			if parts.length() != 2: ok = false
			else:
				cat = parts.get(0, "")
				amt = parts.get(1, "")
		if ok and cat.length() == 0: ok = false
		c := if ok: cents(amt) else: -1
		if c < 0:
			bad += 1
			continue
		prev := totals.get_or(cat, 0)
		totals[cat] = prev + c
	var keys = List[String]()
	for e in totals.entries():
		keys.append(e.key.clone())
	keys.sort()
	for k in keys:
		t := totals.get_or(k, 0)
		f := t % 100
		print("{k}: {t / 100}.{if f < 10: "0" else: ""}{f}")
	if bad > 0: print("skipped: {bad}")
