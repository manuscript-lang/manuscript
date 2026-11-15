import lines from "@std/io/streams.ms"
import stdin from "@std/io/io.ms"

lower := "abcdefghijklmnopqrstuvwxyz"
upper := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn shift_char(c: String, k: Int) String:
	if i := lower.index_of(c):
		return lower.slice((i + k) % 26, (i + k) % 26 + 1).get("?").clone()
	if i := upper.index_of(c):
		return upper.slice((i + k) % 26, (i + k) % 26 + 1).get("?").clone()
	return c.clone()

fn is_digit(c: String) Bool:
	return upper.index_of(c).is_none() and "0123456789".index_of(c).is_some() and c.length() == 1

fn caesar_key(key: String) Int?:
	cs := key.chars()
	var start = 0
	var neg = false
	if cs.length() > 0 and cs.get(0, "") == "-":
		start = 1
		neg = true
	n := cs.length() - start
	if n < 1 or n > 7: return none
	var v = 0
	for i in start..cs.length():
		c := cs.get(i, "")
		if not is_digit(c): return none
		v = v * 10 + "0123456789".index_of(c).get(0)
	if neg: return 0 - v
	return v

fn is_alpha(c: String) Bool:
	return c.length() == 1 and (lower.index_of(c).is_some() or upper.index_of(c).is_some())

fn process(line: String) String:
	parts := line.split(" ")
	if parts.length() < 4: return "error: bad command"
	var text = ""
	for i in 3..parts.length():
		if i > 3: text = text + " "
		text = text + parts.get(i, "")
	if text.length() == 0: return "error: bad command"
	cipher := parts.get(0, "")
	mode := parts.get(1, "")
	key := parts.get(2, "")
	if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
	if mode != "enc" and mode != "dec": return "error: bad mode"
	sign := if mode == "enc": 1 else: -1
	var out = ""
	if cipher == "caesar":
		k := caesar_key(key)
		if k.is_none(): return "error: bad key"
		shift := ((k.get(0) * sign) % 26 + 26) % 26
		for c in text.chars():
			out = out + shift_char(c, shift)
		return out
	if key.length() == 0: return "error: bad key"
	var shifts = List[Int]()
	for c in key.chars():
		if not is_alpha(c): return "error: bad key"
		i := lower.index_of(c).get(upper.index_of(c).get(0))
		shifts.append(((i * sign) % 26 + 26) % 26)
	var p = 0
	for c in text.chars():
		if is_alpha(c):
			out = out + shift_char(c, shifts.get(p % shifts.length(), 0))
			p += 1
		else:
			out = out + c
	return out

// ms: allow_effect std.console.write
fn main() Unit!:
	for line in lines(stdin()):
		if line.trim().length() == 0: continue
		print(process(line))
