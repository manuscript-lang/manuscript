// conform: tags=testing,tier-io
// conform: phase=test
import (
	expect_equal from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

fn tick() Void!:
	return sleep(milliseconds(1)).wait()

type Bag:
	names List[String]
	index Map[String, List[Int]]
	note String?

fn fill(n Int) Bag!:
	var bag = Bag(names: [], index: Map[String, List[Int]](), note: null)

	for i in 0..n:
		name := f"name-{i}"
		bag.names.append(name.clone())

		var slots List[Int] = []

		for j in 0..3:
			slots.append(i * j)
			tick()?

		bag.index[name] = slots

	return ok(bag)

fn merge(var a Bag, var b Bag) Bag!:
	for name in b.names:
		tick()?
		a.names.append(name.clone())

	for key in b.index.keys():
		tick()?

		v := b.index.get(key)
		if v != null:
			a.index[key.clone()] = v.clone()

	a.note = "merged"
	return ok(a.clone())

test "owned values moved across parks by value and by var":
	var left = fill(3)?
	var right = fill(4)?
	merged := merge(left, right)?
	expect_equal(merged.names.length(), 7)?
