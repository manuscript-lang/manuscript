// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Stat:
	count: Int
	sum: Int

fn name_of(i: Int) String:
	return "key-{i % 300}"

test "a probe after a contains-guarded insert reads the entry of either path":
	var stats: Map[String, Stat] = {}
	for i in 0..3000:
		name := name_of(i)
		if not stats.contains(name): stats[name.clone()] = Stat(0, 0)
		stats[name].count += 1
		stats[name].sum += i
	var count = 0
	var sum = 0
	for e in stats.entries():
		count += e.value.count
		sum += e.value.sum
	stats.length() | expect_equal(300)?
	count | expect_equal(3000)?
	sum | expect_equal(4498500)?

test "a growing insert on the absent path does not leave a stale entry":
	var m: Map[Int, Stat] = {}
	for i in 0..2000:
		k := i % 1500
		if not m.contains(k): m[k] = Stat(0, 0)
		m[k].count += 1
	var total = 0
	for e in m.entries(): total += e.value.count
	total | expect_equal(2000)?
	m.length() | expect_equal(1500)?

test "a key that is present on one path and inserted on the other is found":
	var m: Map[String, Int] = {}
	m["a"] = 1
	for k in ["a", "b", "a", "c", "b"]:
		if not m.contains(k): m[k.clone()] = 0
		m[k] += 10
	m["a"] | expect_equal(21)?
	m["b"] | expect_equal(20)?
	m["c"] | expect_equal(10)?
