import stdin from "@std/io/io.ms"
import read_all from "@std/io/streams.ms"

fn digits(s: String) Bool:
	return s.length() > 0 and s.trim_start_chars("0123456789") == ""

fn cents(a: String) Int?:
	parts := a.split(".")
	if parts.length() == 1:
		if not digits(parts[0]):
			return none
		return parts[0].parse_int().map(fn x: x * 100)
	if parts.length() != 2:
		return none
	w := parts[0]
	f := parts[1]
	if not digits(w) or not digits(f) or f.length() > 2:
		return none
	wi := w.parse_int().get(-1)
	fi := f.parse_int().get(-1)
	if wi < 0 or fi < 0:
		return none
	return wi * 100 + (if f.length() == 1: fi * 10 else: fi)

fn two(n: Int) String:
	r := n % 100
	return "{n / 100}.{if r < 10: "0" else: ""}{r}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	bytes := read_all(stdin())?
	text := bytes.decode_utf8().ok_or(Error("bad utf8"))?
	var totals = Map[String, Int]()
	var skipped = 0
	for line in text.lines():
		if line.trim() == "":
			continue
		var cat = ""
		var amt = ""
		var good = false
		if line.starts_with("\""):
			rest := line.slice(1, line.length())?
			parts := rest.split("\"", max_parts: 2)
			if parts.length() == 2 and parts[1].starts_with(","):
				cat = parts[0].clone()
				amt = parts[1].slice(1, parts[1].length())?
				good = true
		else:
			parts := line.split(",")
			if parts.length() == 2:
				cat = parts[0].clone()
				amt = parts[1].clone()
				good = true
		if good and cat != "":
			if c := cents(amt):
				prev := totals.get_or(cat, 0)
				totals[cat] = prev + c
				continue
		skipped += 1
	keys := totals.keys().sorted()
	for k in keys:
		print("{k}: {two(totals.get_or(k, 0))}")
	if skipped > 0:
		print("skipped: {skipped}")
