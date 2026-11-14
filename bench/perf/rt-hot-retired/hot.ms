import (
	Bytes from "@std/bytes.ms",
	StringBuilder from "@std/string_builder.ms",
	monotonic from "@std/time.ms",
)

fn us(a: Int, b: Int) Int:
	return (b - a) / 1000

fn set_contains(s: Set[Int], n: Int) Int:
	var hits = 0
	for r in 0..n:
		for i in 0..1000:
			if s.contains(i * 3 + r):
				hits += 1
	return hits

fn map_int_get(m: Map[Int, Int], n: Int) Int:
	var t = 0
	for r in 0..n:
		for i in 0..1000:
			t += m.get(i * 3 + r).get(0)
	return t

fn map_str_get(m: Map[String, Int], keys: List[String], n: Int) Int:
	var t = 0
	for r in 0..n:
		for k in keys:
			t += m.get(k).get(0)
	return t

fn builder(n: Int) Int:
	var total = 0

	for r in 0..n:
		var sb = StringBuilder()

		for i in 0..100:
			sb.append("ab")
			sb.append("cdefghijklmnopqrst")

		total += sb.to_string().length()

	return total

fn read_words(b: Bytes, n: Int) Int:
	var s = 0
	for r in 0..n:
		for i in 0..(b.length() - 8):
			s += b.int32_le(i).get(0).to_int()
	return s

fn views(text: String, n: Int) Int:
	var s = 0
	for r in 0..n:
		for i in 0..(text.length() - 8):
			s += text.view(i, i + 5).length()
	return s

fn main() Unit:
	var set = Set[Int]()
	var mi = Map[Int, Int]()
	var ms = Map[String, Int]()
	var keys = List[String]()

	for i in 0..1000:
		set.add(i * 2)
		mi.add(i * 2, i)

		k := "key{i}"
		ms.add(k.clone(), i)
		keys.append(k)

	b := "abcdefghij".repeat(100).get().to_bytes()
	text := "abcdefghij".repeat(100).get()
	t0 := monotonic().tick
	a1 := set_contains(set, 3000)
	t1 := monotonic().tick
	a2 := map_int_get(mi, 3000)
	t2 := monotonic().tick
	a3 := map_str_get(ms, keys, 3000)
	t3 := monotonic().tick
	a4 := builder(20000)
	t4 := monotonic().tick
	a5 := read_words(b, 3000)
	t5 := monotonic().tick
	a6 := views(text, 3000)
	t6 := monotonic().tick
	print("set-contains {us(t0, t1)} {a1}")
	print("map-int-get {us(t1, t2)} {a2}")
	print("map-str-get {us(t2, t3)} {a3}")
	print("builder {us(t3, t4)} {a4}")
	print("bytes-int32 {us(t4, t5)} {a5}")
	print("view {us(t5, t6)} {a6}")
