import monotonic from "@std/time.ms"
import PriorityQueue from "@std/collections/queue.ms"

type Rec:
	id: Int
	name: String
	tags: List[String]

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn stop(name: String, t0: Int, chk: Int) Unit:
	now := monotonic().tick
	print("{name} {(now - t0) / 1000} {chk}")

fn base() List[Int]:
	var xs: List[Int] = []
	for i in 0..2000000:
		xs.append(i % 1000)
	return xs

fn l_distinct() Int:
	return base().distinct().length()

fn l_reversed() Int:
	return base().reversed()[0]

fn l_filter_map() Int:
	return base().filter(fn v: v % 2 == 0).map(fn v: v * 3).length()

fn l_contains() Int:
	xs := base()
	var t = 0
	for i in 0..200:
		if xs.contains(999 + i): t += 1
	return t

fn l_clone_nested() Int:
	var rs: List[Rec] = []
	for i in 0..200000:
		rs.append(Rec(i, "name-{i}", ["a", "b", "c"]))
	var t = 0
	for k in 0..5:
		c := rs.clone()
		t += c.length() + c[k].tags.length()
	return t

fn l_insert_remove() Int:
	var xs: List[Int] = []
	for i in 0..50000:
		xs.insert(xs.length() / 2, i)
	var t = 0
	while xs.length() > 0:
		xs.remove(xs.length() / 3)
		t += 1
	return t

fn l_sort_records_str() Int:
	var rs: List[Rec] = []
	var x = 1
	for i in 0..300000:
		x = lcg(x)
		rs.append(Rec(i, "user-name-{x}", []))
	rs.sort(fn a, b: a.name.compare(b.name))
	return rs[0].id + rs[299999].id

fn l_group_words() Int:
	var m: Map[String, List[Int]] = {}
	var x = 1
	for i in 0..1000000:
		x = lcg(x)
		k := "w{x % 20000}"
		if not m.contains(k): m[k.clone()] = []
		m[k].append(i)
	var t = 0
	for k in m.keys():
		t += m[k].length()
	return t

fn l_map_keys_sorted() Int:
	var m: Map[Int, Int] = {}
	for i in 0..500000:
		m[i * 7 % 1000003] = i
	ks := m.keys().sorted(fn a, b: a - b)
	return ks[0] + ks[499999]

fn l_pq() Int:
	var q = PriorityQueue[Int]()
	var x = 1
	for i in 0..500000:
		x = lcg(x)
		q.enqueue(x)
	var t = 0
	while q.length() > 0:
		t += q.dequeue().get() % 7
	return t

fn l_join_split() Int:
	var parts: List[String] = []
	for i in 0..500000:
		parts.append("item{i}")
	s := parts.join(",")
	back := s.split(",")
	return back.length() + s.length()

fn l_slices() Int:
	xs := base()
	var t = 0
	for i in 0..2000:
		t += xs.slice(i, i + 5000).get([]).length()
	return t

fn l_enumerate_zip() Int:
	xs := base()
	var t = 0
	for e in xs.entries():
		t += e.index * e.value % 7
	return t

fn l_set_strings() Int:
	var s = Set[String]()
	for i in 0..500000:
		s.add("str-{i % 100000}")
	return s.length()

fn l_flatten() Int:
	var ll: List[List[Int]] = []
	for i in 0..200000:
		ll.append([i, i + 1, i + 2, i + 3])
	return ll.flat_map(fn r: r).length()

fn main() Unit:
	t_l_distinct := monotonic().tick
	stop("l_distinct", t_l_distinct, l_distinct())
	t_l_reversed := monotonic().tick
	stop("l_reversed", t_l_reversed, l_reversed())
	t_l_filter_map := monotonic().tick
	stop("l_filter_map", t_l_filter_map, l_filter_map())
	t_l_contains := monotonic().tick
	stop("l_contains", t_l_contains, l_contains())
	t_l_clone_nested := monotonic().tick
	stop("l_clone_nested", t_l_clone_nested, l_clone_nested())
	t_l_insert_remove := monotonic().tick
	stop("l_insert_remove", t_l_insert_remove, l_insert_remove())
	t_l_sort_records_str := monotonic().tick
	stop("l_sort_records_str", t_l_sort_records_str, l_sort_records_str())
	t_l_group_words := monotonic().tick
	stop("l_group_words", t_l_group_words, l_group_words())
	t_l_map_keys_sorted := monotonic().tick
	stop("l_map_keys_sorted", t_l_map_keys_sorted, l_map_keys_sorted())
	t_l_pq := monotonic().tick
	stop("l_pq", t_l_pq, l_pq())
	t_l_join_split := monotonic().tick
	stop("l_join_split", t_l_join_split, l_join_split())
	t_l_slices := monotonic().tick
	stop("l_slices", t_l_slices, l_slices())
	t_l_enumerate_zip := monotonic().tick
	stop("l_enumerate_zip", t_l_enumerate_zip, l_enumerate_zip())
	t_l_set_strings := monotonic().tick
	stop("l_set_strings", t_l_set_strings, l_set_strings())
	t_l_flatten := monotonic().tick
	stop("l_flatten", t_l_flatten, l_flatten())
