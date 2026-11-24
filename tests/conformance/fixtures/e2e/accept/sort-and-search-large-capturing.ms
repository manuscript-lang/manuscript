// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Pair from "@std/collections/collections.ms",
	expect_equal from "@std/test/test.ms",
)

// Sorts with a comparator that captures a variable, over lists large enough to leave
// the insertion-sort size, and `binary_search` over every shape of list: results must
// match a straightforward reference.
type Row:
	key Int
	id Int
	name String

fn rows(count Int) List[Row]:
	var out List[Row] = []
	var x = 11

	for i in 0..count:
		x = (x * 1103515245 + 12345) % 2147483648
		out.append(Row(key: x % 20, id: i, name: f"row-name-longer-than-inline-{i}"))

	return out

fn ordered_stably(list List[Row], weights List[Int]) Bool:
	for i in 1..list.length():
		a := list[i - 1]
		b := list[i]
		wa := weights[a.key]
		wb := weights[b.key]
		if wa > wb or (wa == wb and a.id > b.id): return false

	return true

test "a captured list orders owning records stably":
	var weights List[Int] = []
	for i in 0..20:
		weights.append(i % 5)

	sorted := rows(700).sorted((a, b) => weights[a.key] - weights[b.key])
	expect_equal(sorted.length(), 700)?
	expect_equal(ordered_stably(sorted, weights), true)?

test "a captured scalar orders plain integers, and a counter it updates is visible":
	var calls = 0
	scale := 3
	var xs List[Int] = []
	for i in 0..300:
		xs.append((i * 7919) % 211)

	ys := xs.sorted(
		fn a,
		b:
			calls += 1
			return b * scale - a * scale
	)

	expect_equal(ys[0], 210)?
	expect_equal(ys[299] <= ys[0], true)?
	expect_equal(calls > 299, true)?

test "sorted_by_key orders large lists by a captured key":
	offset := 5
	sorted := rows(400).sorted_by_key(r => (r.key + offset) % 7)

	for i in 1..sorted.length():
		a := (sorted[i - 1].key + offset) % 7
		b := (sorted[i].key + offset) % 7
		expect_equal(a <= b, true)?
		if a == b: expect_equal(sorted[i - 1].id < sorted[i].id, true)?

fn reference(xs List[Int], value Int) Int:
	var at = 0
	while at < xs.length() and xs[at] < value:
		at += 1
	return at

test "binary_search agrees with a linear scan on every shape":
	for size in 0..40:
		var xs List[Int] = []
		for i in 0..size:
			xs.append(i / 3 * 2)

		for value in - 2..(size / 3 * 2 + 4):
			found := xs.binary_search(value)
			at := reference(xs, value)
			expect_equal(found.index, at)?
			expect_equal(found.found, at < xs.length() and xs[at] == value)?

test "binary_search finds the first of equal elements in a large list":
	var xs List[Int] = []
	for i in 0..5000:
		xs.append(i / 7)
	expect_equal(xs.binary_search(100).index, 700)?
	expect_equal(xs.binary_search(100).found, true)?
	expect_equal(xs.binary_search(714).index, 4998)?
	expect_equal(xs.binary_search(715).index, 5000)?
	expect_equal(xs.binary_search(715).found, false)?

test "binary_search works on strings":
	words := ["apple", "fig", "kiwi", "pear"]
	expect_equal(words.binary_search("kiwi").index, 2)?
	expect_equal(words.binary_search("grape").index, 2)?
	expect_equal(words.binary_search("grape").found, false)?
	expect_equal(words.binary_search("zebra").index, 4)?

type Wide:
	a Int
	b Int
	c Int
	d Int

test "reverse and reversed handle one to four word slots and owning slots":
	for size in 0..9:
		var ints List[Int] = []
		var pairs List[Pair[Int, Int]] = []
		var triples List[Pair[Int, Pair[Int, Int]]] = []
		var wides List[Wide] = []
		var names List[String] = []

		for i in 0..size:
			ints.append(i)
			pairs.append(Pair(i, i * 2))
			triples.append(Pair(i, Pair(i * 2, i * 3)))
			wides.append(Wide(i, i + 1, i + 2, i + 3))
			names.append(f"name-longer-than-inline-{i}")

		flipped := ints.reversed()
		moved := wides.reversed()

		for i in 0..size:
			expect_equal(flipped[i], size - 1 - i)?
			expect_equal(pairs.reversed()[i].first, size - 1 - i)?
			expect_equal(triples.reversed()[i].second.second, (size - 1 - i) * 3)?
			expect_equal(moved[i].d, size - 1 - i + 3)?
			expect_equal(names.reversed()[i], f"name-longer-than-inline-{size - 1 - i}")?

		pairs.reverse()
		wides.reverse()
		names.reverse()
		ints.reverse()

		for i in 0..size:
			expect_equal(ints[i], size - 1 - i)?
			expect_equal(pairs[i].second, (size - 1 - i) * 2)?
			expect_equal(wides[i].a, size - 1 - i)?
			expect_equal(names[i], f"name-longer-than-inline-{size - 1 - i}")?
