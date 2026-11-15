import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"
import from_scalars from "@std/string.ms"

fn sc(v: Int) String: from_scalars([v]).get("?")

fn is_digit(c: Int) Bool: c >= 48 and c <= 57

fn is_letter(c: Int) Bool: (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn valid_int(key: String) Bool:
	var vals = key.scalar_values()
	var start = 0
	if vals.get(0, 0) == 45: start = 1
	n := vals.length() - start
	if n < 1 or n > 7: return false
	for i in start..vals.length():
		if not is_digit(vals.get(i, 0)): return false
	return true

fn shift_char(ch: String, s: Int) String:
	c := ch.scalar_at(0)
	if c >= 65 and c <= 90:
		return sc(65 + ((c - 65 + s) % 26 + 26) % 26)
	if c >= 97 and c <= 122:
		return sc(97 + ((c - 97 + s) % 26 + 26) % 26)
	return ch.clone()

fn process(line: String) String:
	i1 := line.index_of(" ").get(-1)
	if i1 < 0: return "error: bad command"
	rest1 := line.view(i1 + 1, line.length())
	i2 := rest1.index_of(" ").get(-1)
	if i2 < 0: return "error: bad command"
	rest2 := rest1.view(i2 + 1, rest1.length())
	i3 := rest2.index_of(" ").get(-1)
	if i3 < 0: return "error: bad command"
	text := rest2.view(i3 + 1, rest2.length())
	if text.length() == 0: return "error: bad command"
	cipher := line.view(0, i1)
	mode := rest1.view(0, i2)
	key := rest2.view(0, i3)
	if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
	if mode != "enc" and mode != "dec": return "error: bad mode"
	sign := if mode == "enc": 1 else: -1
	var out = ""
	if cipher == "caesar":
		if not valid_int(key): return "error: bad key"
		k := key.parse_int().get(0) % 26
		for ch in text.chars():
			out += shift_char(ch, sign * k)
		return out
	kv := key.scalar_values()
	for c in kv:
		if not is_letter(c): return "error: bad key"
	var shifts = List[Int]()
	for c in kv:
		shifts.append(if c >= 97: c - 97 else: c - 65)
	var pos = 0
	for ch in text.chars():
		if is_letter(ch.scalar_at(0)):
			out += shift_char(ch, sign * shifts.get(pos % shifts.length(), 0))
			pos += 1
		else:
			out += ch
	return out

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(process(line))
