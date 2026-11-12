// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Stat:
	count: Int
	sum: Int

test "repeated entry updates read the current entry":
	var stats: Map[Int, Stat] = {}
	for i in 0..3000:
		k := i % 700
		if not stats.contains(k): stats[k] = Stat(0, 0)
		stats[k].count += 1
		stats[k].sum += i
		if i > stats[k].sum: stats[k].sum = i
	var count = 0
	var sum = 0
	for e in stats.entries():
		count += e.value.count
		sum += e.value.sum
	count | expect_equal(3000)?
	sum | expect_equal(4498500)?

test "an insert between two lookups of one key does not reuse a stale entry":
	var m: Map[Int, Stat] = {}
	m[0] = Stat(1, 1)
	m[0].count += 1
	for i in 1..2000: m[i] = Stat(i, i)
	m[0].count += 1
	m[0].count | expect_equal(3)?
	m[1999].sum | expect_equal(1999)?

test "a removed key is gone after an update":
	var m: Map[Int, Stat] = {}
	m[1] = Stat(1, 1)
	m[1].count += 1
	m.remove(1)
	m.contains(1) | expect_equal(false)?
