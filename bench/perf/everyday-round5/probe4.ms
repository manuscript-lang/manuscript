import (
	flatten from "@std/collections/collections.ms",
	monotonic from "@std/time.ms",
)

type Row:
	name String
	score Int

fn lcg(x Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn stop(name String, t0 Int, chk Int) Void:
	now := monotonic().tick
	print(f"{name} {(now - t0) / 1000} {chk}")

fn words(n Int) List[String]:
	var out List[String] = []
	var x = 1

	for i in 0..n:
		x = lcg(x)
		out.append(f"w{x % 20000}")

	return out

fn z_top_k() Int:
	ws := words(1000000)
	c := ws.counts()
	var rows List[Row] = []
	for e in c.entries():
		rows.append(Row(e.key.clone(), e.value))

	top := rows.sorted(
		fn a,
		b: if a.score != b.score: b.score - a.score else: a.name.compare(b.name)
	).take(10)
	return top[0].score + top[9].score + c.length()

fn z_insert_front() Int:
	var xs List[Int] = []
	for i in 0..30000:
		xs.insert(0, i)
	return xs[0] + xs.length()

fn z_concat_loop() Int:
	var xs List[Int] = []
	for i in 0..20000:
		xs = xs.concat([i, i + 1])
	return xs.length()

fn z_contains_strings() Int:
	ws := words(3000)
	var t = 0
	for i in 0..3000:
		if ws.contains(f"w{i}"): t += 1
	return t

fn z_remove_mid() Int:
	var xs List[Int] = []
	for i in 0..60000:
		xs.append(i)

	var t = 0

	while xs.length() > 10:
		xs.remove(xs.length() / 2)
		t += 1

	return t

fn z_distinct_strings() Int:
	ws := words(1000000)
	return ws.distinct().length()

fn z_group_rows() Int:
	var rows List[Row] = []
	for i in 0..1000000:
		rows.append(Row(f"user{i % 3000}", i % 100))

	g := rows.group_by(fn r: r.name.clone())
	var t = 0
	for e in g.entries():
		t += e.value.length()
	return t + g.length()

fn z_keys_sorted() Int:
	var m Map[String, Int] = {}
	for i in 0..300000:
		m[f"key{i}"] = i

	ks := m.keys().sorted()
	return ks.length() + ks[0].length()

fn z_reverse_extend() Int:
	var xs List[Int] = []
	for i in 0..2000000:
		xs.append(i)

	var t = 0

	for r in 0..10:
		ys := xs.reversed()
		var zs List[Int] = []
		zs.extend(ys)
		t += zs[0]

	return t

fn z_slice_loop() Int:
	var xs List[Int] = []
	for i in 0..100000:
		xs.append(i)

	var t = 0

	for i in 0..2000:
		s := xs.slice(i, i + 100).get()
		t += s.length()

	return t

fn z_to_set_union() Int:
	ws := words(500000)
	a := ws.take(250000).to_set()
	b := ws.drop(250000).to_set()
	return a.union(b).length() + a.intersection(b).length()

fn z_flatten_nested() Int:
	var xs List[List[Int]] = []
	for i in 0..200000:
		xs.append([i, i + 1, i + 2, i + 3])

	var t = 0
	for r in 0..10:
		t += flatten(xs).length()
	return t

fn run(name String, f fn() Int) Void:
	t0 := monotonic().tick
	c := f()
	stop(name, t0, c)

fn main() Void:
	run("z_top_k", z_top_k)
	run("z_insert_front", z_insert_front)
	run("z_concat_loop", z_concat_loop)
	run("z_contains_strings", z_contains_strings)
	run("z_remove_mid", z_remove_mid)
	run("z_distinct_strings", z_distinct_strings)
	run("z_group_rows", z_group_rows)
	run("z_keys_sorted", z_keys_sorted)
	run("z_reverse_extend", z_reverse_extend)
	run("z_slice_loop", z_slice_loop)
	run("z_to_set_union", z_to_set_union)
	run("z_flatten_nested", z_flatten_nested)
