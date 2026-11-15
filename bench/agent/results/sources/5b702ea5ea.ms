import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn letter_info(c: String, lower: Map[String, Int], upper: Map[String, Int]) Int:
	if v := lower.get(c): return v
	if v := upper.get(c): return v + 100
	return -1

fn shift_text(text: String, shifts: List[Int], sign: Int) String:
	lower := "abcdefghijklmnopqrstuvwxyz"
	var lm = Map[String, Int]()
	var um = Map[String, Int]()
	var i = 0
	for c in lower.chars():
		lm[c.clone()] = i
		um[c.upper()] = i
		i += 1
	var out = ""
	var k = 0
	for c in text.chars():
		info := letter_info(c, lm, um)
		if info < 0:
			out += c
			continue
		is_up := info >= 100
		idx := if is_up: info - 100 else: info
		s := shifts.get(k % shifts.length(), 0)
		k += 1
		n := ((idx + sign * s) % 26 + 26) % 26
		if is_up: out += "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars().get(n, "")
		else: out += lower.chars().get(n, "")
	return out

fn is_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if "0123456789".chars().contains(c) == false: return false
	return true

fn process(line: String) String:
	parts := line.split(" ")
	if parts.length() < 4: return "error: bad command"
	var text = ""
	for i in 3..parts.length():
		if i > 3: text += " "
		text += parts.get(i, "")
	if text.length() == 0: return "error: bad command"
	cipher := parts.get(0, "")
	mode := parts.get(1, "")
	key := parts.get(2, "")
	if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
	if mode != "enc" and mode != "dec": return "error: bad mode"
	sign := if mode == "enc": 1 else: -1
	if cipher == "caesar":
		var neg = false
		var digits = key.clone()
		if key.starts_with("-"):
			neg = true
			digits = key.slice(1, key.length()).get("")
		if not is_digits(digits) or digits.length() > 7: return "error: bad key"
		n := digits.parse_int().get(0)
		return shift_text(text, [if neg: 0 - n else: n], sign)
	if key.length() == 0: return "error: bad key"
	var shifts = List[Int]()
	for c in key.chars():
		idx := "abcdefghijklmnopqrstuvwxyz".chars().index_of(c.lower())
		if i := idx:
			shifts.append(i)
		else: return "error: bad key"
	return shift_text(text, shifts, sign)

// ms: allow_effect std.console.write
// ms: allow_effect std.console.read
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim_chars(" ").length() == 0: continue
		print(process(line))
