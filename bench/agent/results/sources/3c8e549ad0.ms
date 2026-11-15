import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

lower_abc := "abcdefghijklmnopqrstuvwxyz"
upper_abc := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn shift_char(c: String, shift: Int, lo: Map[String, Int], up: Map[String, Int]) String:
	if idx := lo.get(c):
		return lower_abc.chars().get(((idx + shift) % 26 + 26) % 26, c).clone()
	if idx := up.get(c):
		return upper_abc.chars().get(((idx + shift) % 26 + 26) % 26, c).clone()
	return c.clone()

fn is_digits(s: String) Bool:
	for c in s.chars():
		if not "0123456789".contains(c): return false
	return true

fn process(line: String, lo: Map[String, Int], up: Map[String, Int]) String:
	parts := line.split(" ")
	if parts.length() < 4: return "error: bad command"
	var rest = List[String]()
	for i in 3..parts.length():
		rest.append(parts.get(i, "").clone())
	text := rest.join(" ")
	if text.length() == 0: return "error: bad command"
	cipher := parts.get(0, "")
	mode := parts.get(1, "")
	key := parts.get(2, "")
	if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
	if mode != "enc" and mode != "dec": return "error: bad mode"
	sign := if mode == "enc": 1 else: -1
	var out = List[String]()
	if cipher == "caesar":
		var digits = key.clone()
		var neg = false
		if key.starts_with("-"):
			neg = true
			digits = key.slice(1, key.length()).get("")
		if digits.length() < 1 or digits.length() > 7 or not is_digits(digits): return "error: bad key"
		n := digits.parse_int().get(0)
		k := (if neg: 0 - n else: n) % 26
		for c in text.chars():
			out.append(shift_char(c, sign * k, lo, up))
		return out.join("")
	if key.length() == 0: return "error: bad key"
	var shifts = List[Int]()
	for c in key.chars():
		if v := lo.get(c):
			shifts.append(v)
		else if v := up.get(c):
			shifts.append(v)
		else:
			return "error: bad key"
	var pos = 0
	for c in text.chars():
		if lo.get(c).is_some() or up.get(c).is_some():
			out.append(shift_char(c, sign * shifts.get(pos % shifts.length(), 0), lo, up))
			pos += 1
		else:
			out.append(c.clone())
	return out.join("")

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	var lo = Map[String, Int]()
	var up = Map[String, Int]()
	var i = 0
	for c in lower_abc.chars():
		lo[c.clone()] = i
		i += 1
	i = 0
	for c in upper_abc.chars():
		up[c.clone()] = i
		i += 1
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(process(line, lo, up))
