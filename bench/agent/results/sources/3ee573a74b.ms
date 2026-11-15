import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn digits(s: String) Bool:
	if s.is_empty(): return false
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

// amount in cents, or -1 if invalid
fn cents(s: String) Int:
	parts := s.split(".")
	if parts.length() == 1:
		p := parts.get(0, "")
		if not digits(p): return -1
		return (p.parse_int().get(0)) * 100
	if parts.length() != 2: return -1
	whole := parts.get(0, "")
	frac := parts.get(1, "")
	if not digits(whole) or not digits(frac): return -1
	if frac.length() > 2: return -1
	f := (frac.parse_int().get(0)) * (if frac.length() == 1: 10 else: 1)
	return (whole.parse_int().get(0)) * 100 + f

fn pad(n: Int) String:
	if n < 10: return "0{n}"
	return "{n}"

// fills category; returns cents or -1
fn parse_line(line: String, var cat: List[String]) Int:
	var category = ""
	var amount = ""
	if line.starts_with("\""):
		parts := line.split("\"")
		if parts.length() != 3: return -1
		rest := parts.get(2, "")
		if not rest.starts_with(","): return -1
		category = parts.get(1, "")
		amount = rest.view(1, rest.length()).clone()
	else:
		parts := line.split(",")
		if parts.length() != 2: return -1
		category = parts.get(0, "")
		amount = parts.get(1, "")
	if category.is_empty(): return -1
	c := cents(amount)
	if c < 0: return -1
	cat.append(category.clone())
	return c

fn main() Unit!:
	var totals = Map[String, Int]()
	var skipped = 0
	for raw in lines(stdin()):
		line := raw.trim_end_chars("\r")
		if line.is_empty(): continue
		var cat = List[String]()
		c := parse_line(line, var cat)
		if c < 0:
			skipped += 1
			continue
		key := cat.get(0, "")
		totals[key.clone()] = totals.get_or(key, 0) + c
	keys := totals.keys().sorted()
	for k in keys:
		t := totals.get_or(k, 0)
		print("{k}: {t / 100}.{pad(t % 100)}")
	if skipped > 0: print("skipped: {skipped}")
