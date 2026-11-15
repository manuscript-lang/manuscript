import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

lower := "abcdefghijklmnopqrstuvwxyz"
upper := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn shift_char(c: String, amount: Int) String:
	if i := lower.index_of(c):
		j := ((i + amount) % 26 + 26) % 26
		return lower.slice(j, j + 1).get("?").clone()
	if i := upper.index_of(c):
		j := ((i + amount) % 26 + 26) % 26
		return upper.slice(j, j + 1).get("?").clone()
	return c.clone()

fn key_value(c: String) Int:
	if i := lower.index_of(c): return i
	if i := upper.index_of(c): return i
	return -1

fn all_digits(s: String) Bool:
	if s.length() == 0: return false
	for c in s.chars():
		if "0123456789".index_of(c).is_none(): return false
	return true

fn process(line: String) String!:
	n1 := line.index_of(" ").get(-1)
	if n1 < 0: return ok("error: bad command")
	cipher := line.slice(0, n1)?
	rest1 := line.slice(n1 + 1, line.length())?
	n2 := rest1.index_of(" ").get(-1)
	if n2 < 0: return ok("error: bad command")
	mode := rest1.slice(0, n2)?
	rest2 := rest1.slice(n2 + 1, rest1.length())?
	n3 := rest2.index_of(" ").get(-1)
	if n3 < 0: return ok("error: bad command")
	key := rest2.slice(0, n3)?
	text := rest2.slice(n3 + 1, rest2.length())?
	if text.length() == 0: return ok("error: bad command")
	if cipher != "caesar" and cipher != "vigenere": return ok("error: bad cipher")
	if mode != "enc" and mode != "dec": return ok("error: bad mode")
	sign := if mode == "enc": 1 else: -1
	var out = ""
	if cipher == "caesar":
		digits := if key.starts_with("-"): key.slice(1, key.length())? else: key.clone()
		if not all_digits(digits) or digits.length() > 7: return ok("error: bad key")
		mag := digits.parse_int().get(0) % 26
		k := if key.starts_with("-"): -mag else: mag
		for c in text.chars():
			out += shift_char(c, sign * k)
		return ok(out)
	if key.length() == 0: return ok("error: bad key")
	var shifts = List[Int]()
	for c in key.chars():
		v := key_value(c)
		if v < 0: return ok("error: bad key")
		shifts.append(v)
	var pos = 0
	for c in text.chars():
		if key_value(c) >= 0:
			out += shift_char(c, sign * shifts.get(pos % shifts.length(), 0))
			pos += 1
		else:
			out += c
	return ok(out)

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.fields().length() == 0: continue
		r := process(line)
		if x := r:
			print(x)
		else:
			print("error: bad command")
