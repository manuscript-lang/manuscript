// Sorts of 1M records by a comparator, by key shape; `run.sh` compares each against
// Rust.
import monotonic from "@std/time.ms"

type Event:
	id: Int
	kind: Int
	name: String
	score: Int

type Plain:
	id: Int
	kind: Int
	score: Int

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn us(a: Int, b: Int) Int:
	return (b - a) / 1000

fn events(n: Int, m: Int) List[Event]:
	var xs: List[Event] = []
	var x = 1

	for i in 0..n:
		x = lcg(x)
		xs.append(Event(i, x % m, "an-event-name-over-sixteen-bytes", i % 13))

	return xs

fn plains(n: Int, m: Int) List[Plain]:
	var xs: List[Plain] = []
	var x = 1

	for i in 0..n:
		x = lcg(x)
		xs.append(Plain(i, x % m, i % 13))

	return xs

fn main() Unit:
	n := 1000000
	a := events(n, 1000)
	t0 := monotonic().tick
	b := a.sorted(fn p, q: p.kind - q.kind)
	t1 := monotonic().tick
	print("owned-dups-sorted {us(t0, t1)} {b[0].kind + b[n - 1].kind + b[1000].id % 7}")

	var c = events(n, 1000)
	t2 := monotonic().tick
	c.sort(fn p, q: p.kind - q.kind)

	t3 := monotonic().tick
	print(
		"owned-dups-inplace {us(t2, t3)} {c[0].kind + c[n - 1].kind + c[1000].id % 7}"
	)

	d := events(n, 1000000000)
	t4 := monotonic().tick
	e := d.sorted(fn p, q: p.kind - q.kind)
	t5 := monotonic().tick
	print(
		"owned-distinct-sorted {us(t4, t5)} {e[0].kind + e[n - 1].kind + e[1000].id % 7}"
	)

	f := plains(n, 1000)
	t6 := monotonic().tick
	g := f.sorted(fn p, q: p.kind - q.kind)
	t7 := monotonic().tick
	print("plain-dups-sorted {us(t6, t7)} {g[0].kind + g[n - 1].kind + g[1000].id % 7}")

	h := plains(n, 1000000000)
	t8 := monotonic().tick
	i := h.sorted(fn p, q: p.kind - q.kind)
	t9 := monotonic().tick
	print(
		"plain-distinct-sorted {us(t8, t9)} {i[0].kind + i[n - 1].kind + i[1000].id % 7}"
	)

	var s: List[Plain] = []
	for k in 0..n:
		s.append(Plain(k, k / 4 + (k % 3), 0))

	t10 := monotonic().tick
	r := s.sorted(fn p, q: p.kind - q.kind)
	t11 := monotonic().tick
	print(
		"plain-nearly-sorted {us(t10, t11)} {r[0].kind + r[n - 1].kind + r[1000].id % 7}"
	)
