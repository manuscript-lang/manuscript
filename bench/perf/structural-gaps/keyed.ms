type Stat:
	count: Int
	sum: Int
	max: Int

fn case_a() Int:
	var stats: Map[Int, Stat] = {}
	var x = 12345

	for i in 0..2000000:
		x = (x * 1103515245 + 12345) % 2147483648

		k := x % 1000
		if not stats.contains(k): stats[k] = Stat(0, 0, 0)
		stats[k].count += 1
		stats[k].sum += i % 100
		if i % 100 > stats[k].max: stats[k].max = i % 100

	var t = 0
	for e in stats.entries():
		t += e.value.count + e.value.sum + e.value.max
	return t

enum Expr:
	Num(value: Int)
	Add(left: Expr, right: Expr)
	Mul(left: Expr, right: Expr)
	Neg(inner: Expr)

fn build(depth: Int, seed: Int) Expr:
	if depth == 0: return Expr.Num(seed % 10)

	k := seed % 5
	if k == 0: return Expr.Neg(build(depth - 1, seed * 7 + 1))
	if k == 1: return Expr.Mul(
		left: build(depth - 1, seed * 3 + 1),
		right: build(depth - 1, seed + 3),
	)

	return Expr.Add(
		left: build(depth - 1, seed * 5 + 2),
		right: build(depth - 1, seed * 11 + 3),
	)

fn evaluate(expr: Expr) Int:
	match expr:
		Num(value): return value
		Add(left, right): return (evaluate(left) + evaluate(right)) % 1000003
		Mul(left, right): return (evaluate(left) * evaluate(right)) % 1000003
		Neg(inner): return -evaluate(inner)

fn case_b() Int:
	var t = 0

	for r in 0..4:
		e := build(20, r + 2)
		for k in 0..10:
			t = (t + evaluate(e)) % 1000003

	return t

fn case_c() Int:
	var cells: List[Int?] = []

	for i in 0..1000000:
		if i % 3 == 0:
			cells.append(none)
		else:
			cells.append(i)

	var t = 0
	for r in 0..30:
		for c in cells:
			if c.is_some(): t += c.get() % 7
	return t

fn window_sum(xs: List[Int]) Int:
	var s = 0
	for v in xs:
		s += v
	return s

fn case_d() Int:
	var xs: List[Int] = []
	for i in 0..100000:
		xs.append(i % 1000)

	var t = 0
	for r in 0..200:
		for w in 0..100:
			t += window_sum(xs.slice(w * 1000, w * 1000 + 1000).get())
	return t % 1000003

fn case_e() Int:
	var t = 0

	for i in 0..300000:
		line := "  Hello, World number {i}  "
		a := line.trim()
		b := a.replace("World", "there")
		c := b.upper()
		if c.contains("THERE"): t += c.length()

	return t

fn case_f() Int:
	var seen: Set[Int] = Set[Int]()
	var x = 12345
	var dup = 0

	for i in 0..3000000:
		x = (x * 1103515245 + 12345) % 2147483648

		k := x % 200000

		if seen.contains(k):
			dup += 1
		else:
			seen.add(k)

	return dup + seen.length()

fn main() Unit:
	print("{case_a()} {case_b()} {case_c()} {case_d()} {case_e()} {case_f()}")
