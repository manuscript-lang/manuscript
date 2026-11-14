import (
	Deque from "@std/collections/deque.ms",
	monotonic from "@std/time.ms",
)

type Acc:
	name: String
	balance: Int
	history: List[Int]

type Pt:
	x: Int
	y: Int

enum Shape:
	Circle(r: Int)
	Rect(w: Int, h: Int)
	Tri(a: Int, b: Int, c: Int)

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn stop(name: String, t0: Int, chk: Int) Unit:
	now := monotonic().tick
	print("{name} {(now - t0) / 1000} {chk}")

fn m_struct_values() Int:
	var m: Map[String, Acc] = {}
	var x = 1

	for i in 0..1000000:
		x = lcg(x)

		k := "acct{x % 10000}"
		if not m.contains(k): m[k.clone()] = Acc(k.clone(), 0, [])
		m[k].balance += i % 100
		if m[k].history.length() < 8: m[k].history.append(i)

	var t = 0
	for e in m.entries():
		t += e.value.balance + e.value.history.length()
	return t

fn m_memo() Int:
	var memo: Map[Int, Int] = {}
	var t = 0

	for s in 1..300000:
		var n = s
		var steps = 0

		while n != 1 and not memo.contains(n):
			if n % 2 == 0: n /= 2
			else: n = 3 * n + 1

			steps += 1

		base := if n == 1: 0 else: memo[n]
		memo[s] = steps + base
		t += memo[s]

	return t

fn m_struct_keys() Int:
	var m: Map[Pt, Int] = {}
	for i in 0..300000:
		m[Pt(i % 700, i / 700)] = i

	var t = 0
	for i in 0..300000:
		t += m[Pt(i % 700, i / 700)]
	return t

fn m_enum_list() Int:
	var xs: List[Shape] = []

	for i in 0..1000000:
		if i % 3 == 0: xs.append(Shape.Circle(i % 10))
		else if i % 3 == 1: xs.append(Shape.Rect(i % 7, i % 5))
		else: xs.append(Shape.Tri(1, 2, 3))

	var t = 0

	for s in xs:
		match s:
			Circle(r): t += 3 * r * r
			Rect(w, h): t += w * h
			Tri(a, b, c): t += a + b + c

	return t

fn m_bfs_grid() Int:
	n := 1000
	var dist: List[Int] = []
	for i in 0..n * n:
		dist.append(-1)

	var q = Deque[Int]()
	dist[0] = 0
	q.push_back(0)

	while q.length() > 0:
		cur := q.pop_front().get()
		x := cur % n
		y := cur / n
		d := dist[cur]

		if x > 0 and dist[cur - 1] < 0:
			dist[cur - 1] = d + 1
			q.push_back(cur - 1)

		if x < n - 1 and dist[cur + 1] < 0:
			dist[cur + 1] = d + 1
			q.push_back(cur + 1)

		if y > 0 and dist[cur - n] < 0:
			dist[cur - n] = d + 1
			q.push_back(cur - n)

		if y < n - 1 and dist[cur + n] < 0:
			dist[cur + n] = d + 1
			q.push_back(cur + n)

	return dist[n * n - 1]

fn m_sort_keyed() Int:
	var xs: List[Pt] = []
	var x = 1

	for i in 0..1000000:
		x = lcg(x)
		xs.append(Pt(x % 1000, i))

	ys := xs.sorted(fn a, b: if a.x != b.x: a.x - b.x else: a.y - b.y)
	return ys[0].y + ys[999999].y

fn m_group_by() Int:
	var xs: List[Int] = []
	for i in 0..1000000:
		xs.append(i * 7 % 1000)

	g := xs.group_by(fn v: v % 100)
	return g.length() + g[5].length()

fn m_fold_sum() Int:
	var xs: List[Int] = []
	for i in 0..3000000:
		xs.append(i)

	a := xs.fold(0, fn acc, v: acc + v % 3)
	b := xs.map(fn v: v * 2).filter(fn v: v % 3 == 0).length()
	return a + b

fn m_list_of_strings() Int:
	var xs: List[String] = []
	for i in 0..500000:
		xs.append("line {i} of text")

	var t = 0
	for s in xs:
		t += s.length()

	ys := xs.map(fn s: s.upper())
	return t + ys[499999].length()

fn m_set_of_pts() Int:
	var s = Set[Pt]()
	for i in 0..500000:
		s.add(Pt(i % 1000, i % 777))

	var t = 0
	for p in s.values():
		t += p.x
	return t + s.length()

fn m_nested_maps() Int:
	var m: Map[Int, Map[Int, Int]] = {}

	for i in 0..500000:
		a := i % 1000
		if not m.contains(a): m[a] = {}
		m[a][i % 997] = i

	var t = 0
	for e in m.entries():
		t += e.value.length()
	return t

fn m_str_build_map() Int:
	var m: Map[String, String] = {}
	for i in 0..200000:
		m["k{i}"] = "value-{i}-{i * 2}"

	var t = 0
	for e in m.entries():
		t += e.value.length()
	return t

fn main() Unit:
	t_m_struct_values := monotonic().tick
	stop("m_struct_values", t_m_struct_values, m_struct_values())

	t_m_memo := monotonic().tick
	stop("m_memo", t_m_memo, m_memo())

	t_m_struct_keys := monotonic().tick
	stop("m_struct_keys", t_m_struct_keys, m_struct_keys())

	t_m_enum_list := monotonic().tick
	stop("m_enum_list", t_m_enum_list, m_enum_list())

	t_m_bfs_grid := monotonic().tick
	stop("m_bfs_grid", t_m_bfs_grid, m_bfs_grid())

	t_m_sort_keyed := monotonic().tick
	stop("m_sort_keyed", t_m_sort_keyed, m_sort_keyed())

	t_m_group_by := monotonic().tick
	stop("m_group_by", t_m_group_by, m_group_by())

	t_m_fold_sum := monotonic().tick
	stop("m_fold_sum", t_m_fold_sum, m_fold_sum())

	t_m_list_of_strings := monotonic().tick
	stop("m_list_of_strings", t_m_list_of_strings, m_list_of_strings())

	t_m_set_of_pts := monotonic().tick
	stop("m_set_of_pts", t_m_set_of_pts, m_set_of_pts())

	t_m_nested_maps := monotonic().tick
	stop("m_nested_maps", t_m_nested_maps, m_nested_maps())

	t_m_str_build_map := monotonic().tick
	stop("m_str_build_map", t_m_str_build_map, m_str_build_map())
