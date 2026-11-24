import (
	stdout from "@std/io/io.ms",
	monotonic from "@std/time.ms",
)

type Body:
	x: Float
	y: Float
	z: Float
	vx: Float
	vy: Float
	vz: Float
	mass: Float

type Grid:
	width: Int
	height: Int
	cells: List[Int]

enum Tree:
	Leaf
	Node(left: Tree, right: Tree)

fn say(text: String) Void:
	_ignored := stdout().write(text)

fn sieve(n: Int) Int:
	var flags: List[Bool] = List[Bool]()
	var i = 0

	while i <= n:
		flags.append(true)
		i += 1

	var count = 0
	i = 2

	while i <= n:
		if flags.get(i):
			count += 1

			var j = i * i

			while j <= n:
				flags.set(j, false)
				j += i

		i += 1

	return count

fn advance(var bodies: List[Body], steps: Int) Float:
	n := bodies.length()
	var s = 0

	while s < steps:
		var i = 0

		while i < n:
			var a = bodies.get(i).clone()
			var j = i + 1

			while j < n:
				var b = bodies.get(j).clone()
				dx := a.x - b.x
				dy := a.y - b.y
				dz := a.z - b.z
				d2 := dx * dx + dy * dy + dz * dz + 0.01
				mag := 0.01 / (d2 * d2)
				a.vx -= dx * b.mass * mag
				a.vy -= dy * b.mass * mag
				a.vz -= dz * b.mass * mag
				b.vx += dx * a.mass * mag
				b.vy += dy * a.mass * mag
				b.vz += dz * a.mass * mag
				bodies.set(j, b)
				j += 1

			bodies.set(i, a)
			i += 1

		i = 0

		while i < n:
			var a = bodies.get(i).clone()
			a.x += 0.01 * a.vx
			a.y += 0.01 * a.vy
			a.z += 0.01 * a.vz
			bodies.set(i, a)
			i += 1

		s += 1

	var e = 0.0
	var k = 0

	while k < n:
		a := bodies.get(k)
		e += a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz)
		k += 1

	return e

fn cell(g: Grid, x: Int, y: Int) Int:
	wx := (x + g.width) % g.width
	wy := (y + g.height) % g.height
	return g.cells.get(wy * g.width + wx)

fn neighbors(g: Grid, x: Int, y: Int) Int:
	var n = 0
	var dy = -1

	while dy <= 1:
		var dx = -1

		while dx <= 1:
			if not (dx == 0 and dy == 0):
				n += cell(g, x + dx, y + dy)
			dx += 1

		dy += 1

	return n

fn step(g: Grid) Grid:
	var next = List[Int]()
	var y = 0

	while y < g.height:
		var x = 0

		while x < g.width:
			n := neighbors(g, x, y)
			alive := cell(g, x, y) == 1

			if n == 3 or (alive and n == 2):
				next.append(1)
			else:
				next.append(0)

			x += 1

		y += 1

	return Grid(g.width, g.height, next)

fn life(gens: Int) Int:
	var cells = List[Int]()
	var i = 0

	while i < 128 * 128:
		if i % 7 == 0 or i % 11 == 0:
			cells.append(1)
		else:
			cells.append(0)

		i += 1

	var g = Grid(128, 128, cells)
	var n = 0

	while n < gens:
		g = step(g)
		n += 1

	return g.cells.fold(0, fn(acc: Int, v: Int) Int: return acc + v)

fn matmul(n: Int) Float:
	var a = List[List[Float]]()
	var b = List[List[Float]]()
	var i = 0

	while i < n:
		var ra = List[Float]()
		var rb = List[Float]()
		var j = 0

		while j < n:
			ra.append((i + j).to_float())
			rb.append((i - j).to_float())
			j += 1

		a.append(ra)
		b.append(rb)
		i += 1

	var total = 0.0
	i = 0

	while i < n:
		var j = 0

		while j < n:
			var s = 0.0
			var k = 0

			while k < n:
				s += a.get(i).get(k) * b.get(k).get(j)
				k += 1

			total += s
			j += 1

		i += 1

	return total

fn make(depth: Int) Tree:
	if depth == 0: return Leaf
	return Node(make(depth - 1), make(depth - 1))

fn check(t: Tree) Int:
	match t:
		Leaf:
			return 1
		Node(l, r):
			return 1 + check(l) + check(r)

fn trees(rounds: Int) Int:
	var total = 0
	var r = 0

	while r < rounds:
		total += check(make(16))
		r += 1

	return total

fn collatz(limit: Int) Int:
	var best = 0
	var n = 1

	while n < limit:
		var x = n
		var steps = 0

		while x != 1:
			if x % 2 == 0:
				x /= 2
			else:
				x = 3 * x + 1

			steps += 1

		if steps > best:
			best = steps
		n += 1

	return best

fn wordfreq(n: Int) Int:
	var m = Map[Int, Int]()
	var i = 0

	while i < n:
		k := (i * 7919) % 5003
		m.update(k, 0, fn count: count + 1)
		i += 1

	return m.length()

type Cx:
	re: Float
	im: Float

fn Cx.mul(o: Cx) Cx: Cx(
	re: self.re * o.re - self.im * o.im,
	im: self.re * o.im + self.im * o.re,
)

fn Cx.add(o: Cx) Cx: Cx(re: self.re + o.re, im: self.im + o.im)

fn Cx.norm2() Float: self.re * self.re + self.im * self.im

fn mandel(n: Int) Int:
	var total = 0

	for y in 0..n:
		for x in 0..n:
			c := Cx(
				re: 3.0 * x.to_float() / n.to_float() - 2.0,
				im: 2.0 * y.to_float() / n.to_float() - 1.0,
			)
			var z = Cx(re: 0.0, im: 0.0)
			var i = 0

			while i < 100 and z.norm2() < 4.0:
				z = z.mul(z).add(c)
				i += 1

			total += i

	return total

type Particle:
	x: Float
	y: Float
	vx: Float
	vy: Float

fn particles(n: Int, steps: Int) Float:
	var ps = List[Particle]()

	for i in 0..n:
		f := i.to_float()
		ps.append(Particle(x: f, y: f * 0.5, vx: 1.0, vy: -1.0))

	for _s in 0..steps:
		for i in 0..n:
			var p = ps.get(i).clone()
			p.x += p.vx * 0.01
			p.y += p.vy * 0.01
			if p.x > 100.0:
				p.vx = -p.vx
			ps.set(i, p)

	var e = 0.0
	for p in ps:
		e += p.x + p.y
	return e

enum Op:
	Push(n: Int)
	Add
	Mul
	Dup
	Swap
	Pop
	JmpNz(target: Int)
	Dec

fn run_vm(code: List[Op], iters: Int) Int:
	var stack = List[Int]()
	var pc = 0
	var acc = 0
	stack.append(iters)

	while pc < code.length():
		match code.get(pc):
			Push(n):
				stack.append(n)
				pc += 1
			Add:
				b := stack.pop() or 0
				a := stack.pop() or 0
				stack.append(a + b)
				pc += 1
			Mul:
				b := stack.pop() or 0
				a := stack.pop() or 0
				stack.append(a * b % 1000003)
				pc += 1
			Dup:
				v := stack.get(stack.length() - 1)
				stack.append(v)
				pc += 1
			Swap:
				b := stack.pop() or 0
				a := stack.pop() or 0
				stack.append(b)
				stack.append(a)
				pc += 1
			Pop:
				acc += stack.pop() or 0
				pc += 1
			JmpNz(target):
				if stack.get(stack.length() - 1) != 0:
					pc = target
				else:
					pc += 1
			Dec:
				v := stack.pop() or 0
				stack.append(v - 1)
				pc += 1

	return acc

fn vm(iters: Int) Int:
	code := [Op.Push(3), Op.Push(7), Op.Mul, Op.Pop, Op.Dec, Op.JmpNz(0), Op.Pop]
	return run_vm(code, iters)

enum Expr:
	Num(n: Int)
	Add(l: Expr, r: Expr)
	Mul(l: Expr, r: Expr)

fn build(d: Int, s: Int) Expr:
	if d == 0: return Expr.Num(s % 10)
	if d % 2 == 0: return Expr.Add(build(d - 1, s * 3 + 1), build(d - 1, s * 7 + 2))

	return Expr.Mul(build(d - 1, s + 1), build(d - 1, s + 3))

fn eval(e: Expr) Int:
	match e:
		Num(n):
			return n
		Add(l, r):
			return (eval(l) + eval(r)) % 1000003
		Mul(l, r):
			return eval(l) * eval(r) % 1000003

fn exprs(d: Int, reps: Int) Int:
	e := build(d, 1)
	var t = 0
	for _i in 0..reps:
		t += eval(e)
	return t

fn closures(n: Int) Int:
	k := 7
	f := fn(x: Int) Int: x * k + 1
	var t = 0
	for i in 0..n:
		t += f(i) % 13

	xs := (0..1000).map(fn x: x * k)
	for _r in 0..(n / 1000):
		t += xs.map(fn x: x + k).filter(fn x: x % 3 == 0).sum()
	return t

fn stencil(n: Int, iters: Int) Int:
	var a = [0].repeated(n * n)
	var b = [0].repeated(n * n)
	for i in 0..(n * n):
		a.set(i, i % 17)

	for _it in 0..iters:
		for y in 1..(n - 1):
			for x in 1..(n - 1):
				v := (
					a.get(y * n + x - 1)
					+ a.get(y * n + x + 1)
					+ a.get((y - 1) * n + x)
					+ a.get((y + 1) * n + x)
				)
				b.set(y * n + x, v % 1009)

		t := a
		a = b
		b = t

	var s = 0
	for v in a:
		s += v
	return s

fn timed(name: String, run: fn() Int) Void:
	t := monotonic()
	r := run()
	say(f"{name} {monotonic().difference(t).to_nanoseconds() / 1000} {r}\n")

fn main() Int:
	timed("sieve_5M", fn() Int: return sieve(5000000))

	timed(
		"nbody_200k",
		fn() Int:
			var bodies = [
				Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0),
				Body(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0),
				Body(0.0, 2.0, 0.0, 1.0, 0.0, 0.0, 1.0),
				Body(0.0, 0.0, 3.0, 0.0, 0.0, 1.0, 1.0),
				Body(4.0, 4.0, 0.0, 0.0, 0.0, 0.0, 0.5),
			]
			return (advance(bodies, 200000) * 1000.0).truncate_to_int() or 0
	)

	timed("life_128x128_50", fn() Int: return life(50))
	timed("matmul_200", fn() Int: return matmul(200).truncate_to_int() or 0)
	timed("trees_d16_x20", fn() Int: return trees(20))
	timed("collatz_1M", fn() Int: return collatz(1000000))
	timed("map_count_2M", fn() Int: return wordfreq(2000000))
	timed("mandel_400", fn() Int: return mandel(400))
	timed(
		"particles_1k_5k",
		fn() Int: return particles(1000, 5000).truncate_to_int() or 0
	)
	timed("vm_5M", fn() Int: return vm(5000000))
	timed("expr_d20_x20", fn() Int: return exprs(20, 20))
	timed("closures_20M", fn() Int: return closures(20000000))
	timed("stencil_1000_20", fn() Int: return stencil(1000, 20))
	return 0
