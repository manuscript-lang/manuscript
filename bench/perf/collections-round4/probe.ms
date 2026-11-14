import monotonic from "@std/time.ms"

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn stop(name: String, t0: Int, chk: Int) Unit:
	now := monotonic().tick
	print("{name} {(now - t0) / 1000} {chk}")

fn n_sort_floats() Int:
	var xs: List[Float] = []
	var x = 1

	for i in 0..2000000:
		x = lcg(x)
		xs.append(x.to_float() / 7.0)

	xs.sort(fn a, b: if a < b: -1 else if a > b: 1 else: 0)
	return xs[0].truncate_to_int().get(0) + xs[1999999].truncate_to_int().get(0)

fn n_sort_strings_default() Int:
	var xs: List[String] = []
	var x = 1

	for i in 0..300000:
		x = lcg(x)
		xs.append("name-{x % 100000}-suffix")

	ys := xs.sorted()
	return ys[0].length() + ys[299999].length()

fn n_index_of_strings() Int:
	var xs: List[String] = []
	for i in 0..2000:
		xs.append("item-number-{i}")

	var t = 0
	for i in 0..20000:
		t += xs.index_of("item-number-{i % 2000}").get(0)
	return t

fn n_remove_front() Int:
	var xs: List[Int] = []
	for i in 0..100000:
		xs.append(i)

	var t = 0

	while xs.length() > 0:
		xs.remove(0)
		t += 1

	return t

fn n_min_max_sum() Int:
	var xs: List[Int] = []
	for i in 0..3000000:
		xs.append((i * 7919) % 100003)

	var lo = xs[0]
	var hi = xs[0]
	var s = 0

	for v in xs:
		if v < lo: lo = v
		if v > hi: hi = v
		s += v

	return lo + hi + s

fn n_windows() Int:
	var xs: List[Int] = []
	for i in 0..1000000:
		xs.append(i % 100)

	var t = 0
	for i in 0..xs.length() - 3:
		t += xs[i] + xs[i + 1] * xs[i + 2] - xs[i + 3]
	return t

fn n_dedupe_sorted() Int:
	var xs: List[Int] = []
	var x = 1

	for i in 0..1000000:
		x = lcg(x)
		xs.append(x % 50000)

	ys := xs.sorted(fn a, b: a - b)
	var out: List[Int] = []
	for v in ys:
		if out.length() == 0 or out[out.length() - 1] != v: out.append(v)
	return out.length()

fn n_list_clone_modify() Int:
	var base: List[List[Int]] = []

	for i in 0..1000:
		var r: List[Int] = []
		for j in 0..100:
			r.append(i + j)
		base.append(r)

	var t = 0

	for k in 0..200:
		var c = base.clone()
		c[k][0] = 99
		t += c[k][0] + c.length()

	return t

fn n_closure_list() Int:
	var fs: List[fn(Int) Int] = []
	for i in 0..1000:
		fs.append(fn v: v + i)

	var t = 0
	for r in 0..2000:
		for f in fs:
			t += f(r)
	return t

fn n_string_set_ops() Int:
	var a = Set[String]()
	var b = Set[String]()

	for i in 0..200000:
		a.add("s{i}")
		b.add("s{i * 2}")

	return a.intersection(b).length() + a.union(b).length()

fn main() Unit:
	t_n_sort_floats := monotonic().tick
	stop("n_sort_floats", t_n_sort_floats, n_sort_floats())

	t_n_sort_strings_default := monotonic().tick
	stop("n_sort_strings_default", t_n_sort_strings_default, n_sort_strings_default())

	t_n_index_of_strings := monotonic().tick
	stop("n_index_of_strings", t_n_index_of_strings, n_index_of_strings())

	t_n_remove_front := monotonic().tick
	stop("n_remove_front", t_n_remove_front, n_remove_front())

	t_n_min_max_sum := monotonic().tick
	stop("n_min_max_sum", t_n_min_max_sum, n_min_max_sum())

	t_n_windows := monotonic().tick
	stop("n_windows", t_n_windows, n_windows())

	t_n_dedupe_sorted := monotonic().tick
	stop("n_dedupe_sorted", t_n_dedupe_sorted, n_dedupe_sorted())

	t_n_list_clone_modify := monotonic().tick
	stop("n_list_clone_modify", t_n_list_clone_modify, n_list_clone_modify())

	t_n_closure_list := monotonic().tick
	stop("n_closure_list", t_n_closure_list, n_closure_list())

	t_n_string_set_ops := monotonic().tick
	stop("n_string_set_ops", t_n_string_set_ops, n_string_set_ops())
