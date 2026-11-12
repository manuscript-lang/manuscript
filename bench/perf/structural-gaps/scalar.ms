import Bytes from "@std/bytes.ms"
import bit_and, bit_xor, shift_left, shift_right_unsigned, wrapping_multiply, wrapping_add from "@std/math/math.ms"

fn fnv(data: Bytes) Int:
	var h = 1469598103934665603
	for i in 0..data.length():
		h = wrapping_multiply(bit_xor(h, data[i].to_int()), 1099511628211)
	return h

fn case_a() Int:
	data := "the quick brown fox jumps over the lazy dog, again and again and again".repeat(1000).get("").to_bytes()
	var t = 0
	for r in 0..300:
		t = bit_xor(t, fnv(data))
	return bit_and(t, 1048575)

fn case_b() Int:
	var x = 88172645463325252
	var t = 0
	for i in 0..50000000:
		x = bit_xor(x, shift_left(x, 13))
		x = bit_xor(x, shift_right_unsigned(x, 7))
		x = bit_xor(x, shift_left(x, 17))
		t = wrapping_add(t, bit_and(x, 255))
	return bit_and(t, 1048575)

fn case_c() Int:
	var pix: List[UInt8] = []
	for i in 0..1000000:
		pix.append((i * 31 % 256).to_uint8().get(0))
	var t = 0
	for r in 0..30:
		for i in 0..pix.length():
			v := pix[i].to_int()
			g := (v * 77 + 150 * (255 - v) + 29) / 256
			t += g
	return t % 1000003

fn case_d() Int:
	var xs: List[Int] = []
	for i in 0..100000:
		xs.append(i * 7919 % 100003)
	var t = 0
	for r in 0..300:
		if xs.any(fn v: v == 100002 - r): t += 1
		t += xs.find_index(fn v: v > 99990 - r).get(0)
		if xs.all(fn v: v >= 0): t += 1
	return t

fn kind(word: String) Int:
	match word:
		"if": return 1
		"else": return 2
		"while": return 3
		"for": return 4
		"return": return 5
		"fn": return 6
		_: return 0

fn case_e() Int:
	words := ["if", "x", "else", "while", "name", "for", "return", "fn", "value", "other"]
	var t = 0
	for i in 0..20000000:
		t += kind(words[i % 10])
	return t

fn each(n: Int, f: fn(Int) Unit) Unit:
	for i in 0..n:
		f(i)

fn case_f() Int:
	var total = 0
	var calls = 0
	each(30000000, fn(v: Int) Unit:
		total = (total + v) % 1000003
		calls += 1
	)
	return total + calls

fn main() Unit:
	print("{case_a()} {case_b()} {case_c()} {case_d()} {case_e()} {case_f()}")
