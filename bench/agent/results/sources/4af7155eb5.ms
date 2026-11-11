import (
	stdin, stdout from "@std/io/io.ms",
	collect, lines from "@std/io/streams.ms",
	from_scalars from "@std/string.ms",
)

// Copies scalars cs[a..b) into a fresh list.
fn sub(cs: List[Int], a: Int, b: Int) List[Int]:
	var out = List[Int]()
	var i = a

	while i < b:
		out.append(cs[i])
		i += 1

	return out

fn text_of(cs: List[Int]) String:
	return from_scalars(cs).get()

// Index of the first space at or after start, or -1.
fn next_space(cs: List[Int], start: Int) Int:
	var i = start

	while i < cs.length():
		if cs[i] == 32: return i

		i += 1

	return -1

fn blank(cs: List[Int]) Bool:
	for c in cs:
		if c != 32: return false
	return true

fn is_upper(c: Int) Bool:
	return c >= 65 and c <= 90

fn is_lower(c: Int) Bool:
	return c >= 97 and c <= 122

fn is_letter(c: Int) Bool:
	return is_upper(c) or is_lower(c)

// Zero-based alphabet index of an ASCII letter of either case.
fn letter_index(c: Int) Int:
	if is_lower(c): return c - 97
	return c - 65

fn norm(k: Int) Int:
	return ((k % 26) + 26) % 26

// Shifts a letter forward by k (k may be negative); other scalars are unchanged.
fn shift(c: Int, k: Int) Int:
	a := norm(k)
	if is_upper(c): return 65 + (c - 65 + a) % 26
	if is_lower(c): return 97 + (c - 97 + a) % 26

	return c

// Caesar key: optional leading '-', then 1 to 7 decimal digits.
fn parse_caesar(key: List[Int]) Int?:
	var i = 0
	var neg = false

	if not key.is_empty() and key[0] == 45:
		neg = true
		i = 1

	digits := key.length() - i
	if digits < 1 or digits > 7: return none

	var v = 0

	while i < key.length():
		c := key[i]
		if c < 48 or c > 57: return none

		v = v * 10 + (c - 48)
		i += 1

	if neg: return -v

	return v

// Vigenere key: one or more ASCII letters, as alphabet indexes.
fn vig_key(key: List[Int]) List[Int]?:
	if key.is_empty(): return none

	var out = List[Int]()

	for c in key:
		if not is_letter(c): return none

		out.append(letter_index(c))

	return out

fn process(cs: List[Int]) String:
	s1 := next_space(cs, 0)
	if s1 < 0: return "error: bad command"

	s2 := next_space(cs, s1 + 1)
	if s2 < 0: return "error: bad command"

	s3 := next_space(cs, s2 + 1)
	if s3 < 0 or s3 + 1 >= cs.length(): return "error: bad command"

	cipher := text_of(sub(cs, 0, s1))
	mode := text_of(sub(cs, s1 + 1, s2))
	keyv := sub(cs, s2 + 1, s3)
	text := sub(cs, s3 + 1, cs.length())
	if cipher != "caesar" and cipher != "vigenere": return "error: bad cipher"
	if mode != "enc" and mode != "dec": return "error: bad mode"

	enc := mode == "enc"

	if cipher == "caesar":
		if k := parse_caesar(keyv):
			amt := if not enc: -k else: k
			var res = List[Int]()
			for c in text:
				res.append(shift(c, amt))
			return text_of(res)

		return "error: bad key"

	if kv := vig_key(keyv):
		var res = List[Int]()
		var p = 0

		for c in text:
			if is_letter(c):
				s := kv[p % kv.length()]

				if enc:
					res.append(shift(c, s))
				else:
					res.append(shift(c, -s))

				p += 1
			else:
				res.append(c)

		return text_of(res)

	return "error: bad key"

export fn main() Int:
	var out = ""

	for line in collect(lines(stdin())).get():
		cs := line.scalar_values()
		if blank(cs): continue

		out += process(cs) + "\n"

	stdout().write(out).get()
	return 0
