import (
	PriorityQueue from "@std/collections/queue.ms",
	panic from "@std/core.ms",
	monotonic from "@std/time.ms",
)

enum Expr {
	Num(value Int)
	Add(left Expr, right Expr)
	Mul(left Expr, right Expr)
	Neg(inner Expr)
}

fn build(depth Int, seed Int) Expr {
	if depth == 0 { return Expr.Num(seed % 10) }
	if seed % 3 == 0 {
		return Expr.Add(build(depth - 1, seed * 7 + 1), build(depth - 1, seed * 5 + 2))
	}
	if seed % 3 == 1 {
		return Expr.Mul(build(depth - 1, seed * 3 + 1), build(depth - 1, seed + 4))
	}

	return Expr.Neg(build(depth - 1, seed + 9))
}

fn eval(e Expr) Int {
	match e {
		Num(value) => return value
		Add(left, right) => return (eval(left) + eval(right)) % 1000003
		Mul(left, right) => return (eval(left) * eval(right)) % 1000003
		Neg(inner) => return 0 - eval(inner)
	}
}

fn count(e Expr) Int {
	match e {
		Num(_) => return 1
		Add(left, right) => return 1 + count(left) + count(right)
		Mul(left, right) => return 1 + count(left) + count(right)
		Neg(inner) => return 1 + count(inner)
	}
}

type Item {
	score Int
	id Int
}

fn Item.compare(other Item) Int {
	if self.score != other.score { return self.score - other.score }
	return self.id - other.id
}

type Particle {
	x Float
	y Float
	vx Float
	vy Float
}

fn lcg(x Int) Int {
	return (x * 1103515245 + 12345) % 2147483648
}

fn stop(name String, t0 Int, chk Int) Void {
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")
}

fn x_expr() Int {
	e := build(20, 1)
	var t = count(e)
	for r in 0..10 {
		t += eval(e)
	}
	return t
}

fn x_sort_custom() Int {
	var xs List[Item] = []
	var x = 1

	for i in 0..1000000 {
		x = lcg(x)
		xs.append(Item(x % 5000, i))
	}

	ys := xs.sorted()
	return ys[0].id + ys[999999].id
}

fn collatz(n Int, var memo Map[Int, Int]) Int {
	if n == 1 { return 0 }
	if memo.contains(n) { return memo[n] }

	r := 1 + collatz(if n % 2 == 0 { n / 2 } else { 3 * n + 1 }, memo)
	memo[n] = r
	return r
}

fn x_memo() Int {
	var memo Map[Int, Int] = {}
	var t = 0
	for s in 1..300000 {
		t += collatz(s, memo)
	}
	return t
}

fn compose(f fn(Int) Int, g fn(Int) Int) fn(Int) Int {
	return v => g(f(v))
}

fn x_compose() Int {
	h := compose(compose(v => v + 1, v => v * 3), v => v - 2)
	var t = 0
	for i in 0..30000000 {
		t += h(i)
	}
	return t
}

fn x_particles() Int {
	var ps List[Particle] = []
	for i in 0..100000 {
		ps.append(Particle(i.to_float(), 0.0, 1.0, 0.5))
	}

	for step in 0..100 {
		for i in 0..ps.length() {
			ps[i].x += ps[i].vx * 0.01
			ps[i].y += ps[i].vy * 0.01
			if ps[i].x > 500.0 { ps[i].vx = 0.0 - ps[i].vx }
		}
	}

	var t = 0.0
	for p in ps {
		t += p.x + p.y
	}
	return t.truncate_to_int() or 0
}

fn x_grid_stencil() Int {
	n := 1000
	var g List[List[Int]] = []

	for i in 0..n {
		var row List[Int] = []
		for j in 0..n {
			row.append((i * j) % 17)
		}
		g.append(row)
	}

	var t = 0
	for r in 0..5 {
		for i in 1..n - 1 {
			for j in 1..n - 1 {
				t += g[i - 1][j] + g[i + 1][j] + g[i][j - 1] + g[i][j + 1] - 4 * g[i][j]
			}
		}
	}
	return t
}

fn x_graph_bfs() Int {
	n := 200000
	var adj Map[Int, List[Int]] = {}
	for i in 0..n {
		adj[i] = [(i * 7 + 1) % n, (i * 13 + 5) % n, (i + 1) % n]
	}

	var seen Set[Int] = Set()
	var frontier List[Int] = [0]
	seen.add(0)

	var t = 0

	while frontier.length() > 0 {
		var next List[Int] = []

		for v in frontier {
			for w in adj[v] {
				if not seen.contains(w) {
					seen.add(w)
					next.append(w)
				}
			}
		}

		t += next.length()
		frontier = next
	}

	return t + seen.length()
}

fn x_dijkstra() Int {
	n := 400
	var dist List[Int] = []
	for i in 0..n * n {
		dist.append(1000000000)
	}

	var pq = PriorityQueue[Item]()
	dist[0] = 0
	pq.enqueue(Item(0, 0))

	while not pq.is_empty() {
		it := pq.dequeue() or panic("called Optional.get() on null")
		if it.score > dist[it.id] { continue }

		x := it.id % n
		y := it.id / n
		var k = 0

		while k < 4 {
			nx := if k == 0 { x - 1 } else if k == 1 { x + 1 } else { x }
			ny := if k == 2 { y - 1 } else if k == 3 { y + 1 } else { y }
			k += 1
			if nx < 0 or ny < 0 or nx >= n or ny >= n { continue }

			w := (nx * 31 + ny * 17) % 9 + 1
			nd := it.score + w
			at := ny * n + nx

			if nd < dist[at] {
				dist[at] = nd
				pq.enqueue(Item(nd, at))
			}
		}
	}

	return dist[n * n - 1]
}

fn x_map_records() Int {
	var m Map[String, Item] = {}

	for i in 0..300000 {
		k := f"key-{i % 5000}"

		if m.contains(k) {
			m[k].score += i % 7
			m[k].id += 1
		} else {
			m[k] = Item(i % 7, 1)
		}
	}

	var t = 0
	for e in m.entries() {
		t += e.value.score * e.value.id
	}
	return t
}

fn stage1(v Int) Int! {
	if v % 100003 == 0 { return error(Error("s1")) }
	return ok(v + 1)
}

fn stage2(v Int) Int! {
	if v % 100019 == 0 { return error(Error("s2")) }
	return ok(v * 2)
}

fn stage3(v Int) Int! {
	return ok(v - 3)
}

fn pipeline(v Int) Int! {
	a := stage1(v)?
	b := stage2(a)?
	return stage3(b)
}

fn x_result_pipeline() Int {
	var t = 0

	for i in 1..5000000 {
		r := pipeline(i)

		if v := r {
			t += v
		} else {
			t += 1
		}
	}

	return t
}

fn x_find_first() Int {
	var xs List[Item] = []
	for i in 0..1000 {
		xs.append(Item(i, i))
	}

	var t = 0

	for i in 0..20000 {
		f := xs.find(it => it.score == i % 1000)
		if f != null {
			t += f.id
		}
	}

	return t
}

fn run(name String, f fn() Int) Void {
	t0 := monotonic().tick
	c := f()
	stop(name, t0, c)
}

fn main() Void {
	run("x_expr", x_expr)
	run("x_sort_custom", x_sort_custom)
	run("x_memo", x_memo)
	run("x_compose", x_compose)
	run("x_particles", x_particles)
	run("x_grid_stencil", x_grid_stencil)
	run("x_graph_bfs", x_graph_bfs)
	run("x_dijkstra", x_dijkstra)
	run("x_map_records", x_map_records)
	run("x_result_pipeline", x_result_pipeline)
	run("x_find_first", x_find_first)
}
