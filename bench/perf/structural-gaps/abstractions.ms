type Vec:
	x: Int
	y: Int
	z: Int

fn Vec.add(o: Vec) Vec:
	return Vec(self.x + o.x, self.y + o.y, self.z + o.z)

fn Vec.dot(o: Vec) Int:
	return self.x * o.x + self.y * o.y + self.z * o.z

fn Vec.wrap() Vec:
	return Vec(self.x % 1000, self.y % 1000, self.z % 1000)

fn case_a() Int:
	var p = Vec(1, 2, 3)
	var t = 0

	for i in 0..20000000:
		d := Vec(i % 7, i % 5, i % 3)
		p = p.add(d).wrap()
		t = (t + p.dot(d)) % 1000003

	return t

type Customer:
	name: String
	tier: Int

type Line:
	sku: Int
	qty: Int
	price: Int

type Order:
	id: Int
	customer: Customer
	lines: List[Line]

fn Order.total() Int:
	var s = 0
	for l in self.lines:
		s += l.qty * l.price
	return s

fn case_b() Int:
	var orders: List[Order] = []

	for i in 0..100000:
		var lines: List[Line] = []
		for k in 0..4:
			lines.append(Line(i + k, k + 1, (i * 7 + k) % 100))
		orders.append(Order(i, Customer("c{i % 100}", i % 3), lines))

	var t = 0
	for r in 0..50:
		for o in orders:
			if o.customer.tier != 1:
				t = (t + o.total()) % 1000003
	return t

interface Shape:
	fn area() Int

type Rect:
	w: Int
	h: Int

type Square:
	s: Int

type Tri:
	b: Int
	h: Int

fn Rect.area() Int: return self.w * self.h

fn Square.area() Int: return self.s * self.s

fn Tri.area() Int: return self.b * self.h / 2

fn case_c() Int:
	var shapes: List[Shape] = []

	for i in 0..100000:
		k := i % 3
		if k == 0: shapes.append(Rect(i % 50, 3))
		if k == 1: shapes.append(Square(i % 40))
		if k == 2: shapes.append(Tri(i % 30, 4))

	var t = 0
	for r in 0..100:
		for s in shapes:
			t = (t + s.area()) % 1000003
	return t

fn apply_n(n: Int, f: fn(Int) Int) Int:
	var t = 0
	for i in 0..n:
		t = (t + f(i)) % 1000003
	return t

fn case_d() Int:
	k := 17
	fs: List[fn(Int) Int] := [
		fn(v: Int) Int: v * k,
		fn(v: Int) Int: v + k,
		fn(v: Int) Int: (v % (k + 1))
	]
	var t = 0
	for i in 0..10000000:
		t = (t + fs[i % 3](i)) % 1000003
	return t + apply_n(10000000, fn(v: Int) Int: v * k + 1)

fn largest[T: Comparable](xs: List[T]) Int:
	var best = 0
	for i in 1..xs.length():
		if xs[i].compare(xs[best]) > 0: best = i
	return best

fn case_e() Int:
	var xs: List[Int] = []
	for i in 0..10000:
		xs.append(i * 7919 % 10007)

	var t = 0

	for r in 0..2000:
		xs[r] += r
		t += largest(xs)

	return t

type Stats:
	count: Int
	sum: Int

type Meter:
	name: String
	stats: Stats

fn var Meter.record(v: Int) Unit:
	self.stats.count += 1
	self.stats.sum = (self.stats.sum + v) % 1000003

fn case_f() Int:
	var m = Meter("m", Stats(0, 0))
	for i in 0..30000000:
		m.record(i)
	return m.stats.sum + m.stats.count

fn main() Unit:
	print("{case_a()} {case_b()} {case_c()} {case_d()} {case_e()} {case_f()}")
