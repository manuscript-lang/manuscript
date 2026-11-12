type Stat:
	count: Int
	sum: Int

fn case_a() Int:
	var names: List[String] = []
	for i in 0..2000:
		names.append("user-{i * 7919 % 2003}")
	var stats: Map[String, Stat] = {}
	for i in 0..2000000:
		name := names[i % 2000]
		if not stats.contains(name): stats[name.clone()] = Stat(0, 0)
		stats[name].count += 1
		stats[name].sum += i % 10
	var t = 0
	for e in stats.entries():
		t += e.value.count + e.value.sum
	return t

fn case_b() Int:
	var m: Map[Int, Int] = {}
	for i in 0..200000:
		m[i * 7919 % 200003] = i
	var t = 0
	for r in 0..20:
		for e in m.entries():
			t += e.value % 7
		for k in m.keys():
			t += m[k] % 3
		for v in m.values():
			t += v % 5
	return t

fn case_c() Int:
	var out = ""
	for i in 0..300000:
		fields := ["{i}", "user{i % 97}", "{i * 31 % 1000}", "ok"]
		out += fields.join(",")
		out += "\n"
	return out.length()

fn case_d() Int:
	var xs: List[Int] = []
	for i in 0..2000:
		xs.append(i)
	var t = 0
	for r in 0..200000:
		v := xs[0]
		xs.remove(0)
		xs.insert(1000, v)
		t += xs.pop().get()
		xs.prepend(t % 2000)
	return t % 1000003

type Matrix:
	rows: Int
	cols: Int
	data: List[Float]

fn Matrix.at(i: Int, j: Int) Float:
	return self.data[i * self.cols + j]

fn var Matrix.put(i: Int, j: Int, v: Float) Unit:
	self.data[i * self.cols + j] = v

fn zeros(rows: Int, cols: Int) Matrix:
	return Matrix(rows, cols, [0.0].repeated(rows * cols))

fn multiply(a: Matrix, b: Matrix) Matrix:
	var c = zeros(a.rows, b.cols)
	for i in 0..a.rows:
		for j in 0..b.cols:
			var s = 0.0
			for k in 0..a.cols:
				s += a.at(i, k) * b.at(k, j)
			c.put(i, j, s)
	return c

fn case_e() Int:
	n := 200
	var a = zeros(n, n)
	var b = zeros(n, n)
	for i in 0..n:
		for j in 0..n:
			a.put(i, j, (i + j).to_float() * 0.01)
			b.put(i, j, (i - j).to_float() * 0.02)
	var t = 0.0
	for r in 0..3:
		c := multiply(a, b)
		t += c.at(r, r + 1)
	return t.truncate_to_int().get(0)

type Stack[T]:
	items: List[T]

fn var Stack[T].push(v: T) Unit:
	self.items.append(v)

fn var Stack[T].pop() T?:
	return self.items.pop()

fn Stack[T].size() Int:
	return self.items.length()

fn case_f() Int:
	var s = Stack[Int]([])
	var t = 0
	for i in 0..20000000:
		s.push(i)
		if i % 3 == 2:
			t += s.pop().get(0) % 7
			t += s.pop().get(0) % 5
	return t + s.size()

fn main() Unit:
	print("{case_a()} {case_b()} {case_c()} {case_d()} {case_e()} {case_f()}")
