import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

fn is_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		code := c.scalar_at(0)
		if code < 48 or code > 57: return false
	return true

fn letter_shift(c: String) Int:
	code := c.scalar_at(0)
	if code >= 97 and code <= 122: return code - 97
	return code - 65

fn is_letter(c: String) Bool:
	if c.scalar_length() != 1: return false
	code := c.scalar_at(0)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

fn transform(text: String, shifts: List[Int], vig: Bool, sign: Int) String:
	upper := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".chars()
	lower := "abcdefghijklmnopqrstuvwxyz".chars()
	var out = ""
	var pos = 0
	n := shifts.length()
	for c in text.chars():
		if not is_letter(c):
			out += c
			continue
		s := if vig: shifts.get(pos % n, 0) else: shifts.get(0, 0)
		pos += 1
		code := c.scalar_at(0)
		base := if code >= 97: 97 else: 65
		idx := ((code - base + sign * s) % 26 + 26) % 26
		out += if code >= 97: lower.get(idx, "") else: upper.get(idx, "")
	return out

fn process(line: String) String:
	var parts = List[String]()
	var rest = line.clone()
	for _i in 0..3:
		idx := rest.index_of(" ")
		if idx.is_none(): return "error: bad command"
		i := idx.get(0)
		parts.append(rest.slice(0, i).get(""))
		rest = rest.slice(i + 1, rest.length()).get("")
	cipher := parts.get(0, "")
	mode := parts.get(1, "")
	key := parts.get(2, "")
	text := rest.clone()
	if text.length() == 0: return "error: bad command"
	if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
	if mode != "enc" and mode != "dec": return "error: bad mode"
	sign := if mode == "enc": 1 else: -1
	if cipher == "caesar":
		digits := if key.starts_with("-"): key.slice(1, key.length()).get("") else: key.clone()
		if not is_digits(digits) or digits.length() > 7: return "error: bad key"
		v := digits.parse_int().get(0)
		k := if key.starts_with("-"): 0 - v else: v
		return transform(text, [k % 26], false, sign)
	if key.length() == 0: return "error: bad key"
	var shifts = List[Int]()
	for c in key.chars():
		if not is_letter(c): return "error: bad key"
		shifts.append(letter_shift(c))
	return transform(text, shifts, true, sign)

// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(process(line.trim_end_chars("\r")))
