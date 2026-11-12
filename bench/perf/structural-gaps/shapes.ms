// The same work written two ways: the shape lowering recognizes, and a neighbor that
// reads the same values through a binding, a helper or a combinator chain. Prints
// microseconds per case.
import monotonic from "@std/time.ms"

type P:
	x: Int
	y: Int
	name: String

fn us(a: Int, b: Int) Int:
	return (b - a) / 1000

fn total(ps: List[P]) Int:
	var s = 0
	for p in ps:
		s += p.y
	return s

fn count_o(cs: List[String]) Int:
	var s = 0
	for c in cs:
		if c == "o":
			s += 1
	return s

fn main() Unit:
	var m = Map[Int, P]()
	for i in 0..200000:
		m[i] = P(i, i * 2, "name-of-point-number-{i}")

	t0 := monotonic().tick
	var s1 = 0
	for p in m.values():
		s1 += p.y

	t1 := monotonic().tick
	vals := m.values()
	s2 := total(vals)
	t2 := monotonic().tick
	s3 := total(m.values())
	t3 := monotonic().tick
	print("values-loop {us(t0, t1)} {s1}")
	print("values-bound {us(t1, t2)} {s2}")
	print("values-argument {us(t2, t3)} {s3}")

	text := "the quick brown fox jumps over the lazy dog".repeat(20000).get()
	t4 := monotonic().tick
	var s4 = 0
	for c in text.chars():
		if c == "o":
			s4 += 1

	t5 := monotonic().tick
	s5 := count_o(text.chars())
	t6 := monotonic().tick
	print("chars-loop {us(t4, t5)} {s4}")
	print("chars-argument {us(t5, t6)} {s5}")

	line := "10.0.0.1 - GET /api/v2/item/17 200 12345 extra"
	var s6 = 0

	for i in 0..1000000:
		f := line.split(" ")
		s6 += f[5].length()

	t7 := monotonic().tick
	var s7 = 0

	for i in 0..1000000:
		at := line.index_of(" ").get()
		s7 += line.view(0, at).length()

	t8 := monotonic().tick
	print("split-index {us(t6, t7)} {s6}")
	print("find-view {us(t7, t8)} {s7}")

	var xs: List[Int] = []
	for i in 0..2000000:
		xs.append(i % 1000)

	t9 := monotonic().tick
	s8 := xs.filter(fn v: v % 3 == 0).map(fn v: v * 2).sum()
	t10 := monotonic().tick
	var s9 = 0
	for v in xs:
		if v % 3 == 0:
			s9 += v * 2

	t11 := monotonic().tick
	print("filter-map-sum {us(t9, t10)} {s8}")
	print("hand-loop {us(t10, t11)} {s9}")

	var ps: List[P] = []
	for i in 0..200000:
		ps.append(P(i, i * 2, "name-of-point-number-{i}"))

	t12 := monotonic().tick
	var s10 = 0
	for p in ps.filter(fn p: p.x % 2 == 0):
		s10 += p.y

	t13 := monotonic().tick
	var s11 = 0
	for p in ps:
		if p.x % 2 == 0:
			s11 += p.y

	t14 := monotonic().tick
	print("records-filter-loop {us(t12, t13)} {s10}")
	print("records-hand-loop {us(t13, t14)} {s11}")
