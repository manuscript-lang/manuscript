// Collection probes: each case prints "name microseconds checksum".
import monotonic from "@std/time.ms"

type Node:
	left: Node?
	right: Node?

type P:
	x: Int
	y: Int
	name: String

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn stop(name: String, t0: Int, chk: Int) Unit:
	now := monotonic().tick
	print("{name} {(now - t0) / 1000} {chk}")

fn big_int_map() Int:
	var m: Map[Int, Int] = {}
	var x = 1

	for i in 0..2000000:
		x = lcg(x)
		m[x * 7919 % 4000037] = i

	var t = 0

	for i in 0..2000000:
		x = lcg(x)

		v := m.get(x * 7919 % 4000037)
		if v.is_some(): t += v.get()

	return t + m.length()

fn string_key_map() Int:
	var m: Map[String, Int] = {}
	for i in 0..500000:
		m["key-number-{i}"] = i

	var t = 0
	for i in 0..500000:
		t += m["key-number-{i}"]
	return t

fn map_remove_churn() Int:
	var m: Map[Int, Int] = {}
	var t = 0

	for i in 0..1000000:
		m[i] = i
		if i >= 1000:
			m.remove(i - 1000)

	for e in m.entries():
		t += e.value
	return t + m.length()

fn set_ops() Int:
	var a = Set[Int]()
	var b = Set[Int]()

	for i in 0..500000:
		a.add(i * 3)
		b.add(i * 5)

	u := a.union(b)
	n := a.intersection(b)
	d := a.difference(b)
	return u.length() + n.length() + d.length()

fn sort_ints() Int:
	var xs: List[Int] = []
	var x = 1

	for i in 0..3000000:
		x = lcg(x)
		xs.append(x)

	ys := xs.sorted(fn a, b: a - b)
	return ys[0] + ys[1500000] + ys[2999999]

fn sort_strings() Int:
	var xs: List[String] = []
	var x = 1

	for i in 0..500000:
		x = lcg(x)
		xs.append("s{x}")

	xs.sort(fn a, b: a.compare(b))
	return xs[0].length() + xs[250000].length()

fn struct_list() Int:
	var xs: List[P] = []
	for i in 0..1000000:
		xs.append(P(i, i * 2, "n"))

	var t = 0
	for p in xs:
		t += p.x + p.y

	ys := xs.map(fn p: p.x + 1)
	return t + ys.length()

fn make_tree(d: Int) Node?:
	if d == 0: return Node(none, none)
	return Node(make_tree(d - 1), make_tree(d - 1))

fn count(n: Node?) Int:
	if n.is_none(): return 0

	nn := n.get()
	return 1 + count(nn.left) + count(nn.right)

fn trees() Int:
	var t = 0
	for i in 0..20:
		t += count(make_tree(18))
	return t

fn list_of_lists() Int:
	var g: List[List[Int]] = []

	for i in 0..1500:
		var row: List[Int] = []
		for j in 0..1500:
			row.append(i * 31 + j)
		g.append(row)

	var t = 0
	for i in 1..1499:
		for j in 1..1499:
			t += g[i - 1][j] + g[i + 1][j] + g[i][j - 1] + g[i][j + 1]
	return t

fn list_ops() Int:
	var xs: List[Int] = []
	for i in 0..2000000:
		xs.append(i % 1000)

	d := xs.distinct()
	r := xs.reversed()
	s := xs.filter(fn v: v % 2 == 0).map(fn v: v * 3)
	var t = 0
	for i in 0..200:
		if xs.contains(999 + i): t += 1
	return d.length() + r[0] + s.length() + t

fn main() Unit:
	t_big_int_map := monotonic().tick
	stop("big_int_map", t_big_int_map, big_int_map())

	t_string_key_map := monotonic().tick
	stop("string_key_map", t_string_key_map, string_key_map())

	t_map_remove_churn := monotonic().tick
	stop("map_remove_churn", t_map_remove_churn, map_remove_churn())

	t_set_ops := monotonic().tick
	stop("set_ops", t_set_ops, set_ops())

	t_sort_ints := monotonic().tick
	stop("sort_ints", t_sort_ints, sort_ints())

	t_sort_strings := monotonic().tick
	stop("sort_strings", t_sort_strings, sort_strings())

	t_struct_list := monotonic().tick
	stop("struct_list", t_struct_list, struct_list())

	t_trees := monotonic().tick
	stop("trees", t_trees, trees())

	t_list_of_lists := monotonic().tick
	stop("list_of_lists", t_list_of_lists, list_of_lists())

	t_list_ops := monotonic().tick
	stop("list_ops", t_list_ops, list_ops())
