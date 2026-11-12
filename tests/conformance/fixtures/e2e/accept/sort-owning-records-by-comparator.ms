// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Entry:
	key: Int
	id: Int
	name: String
	tags: List[String]

fn entries(count: Int) List[Entry]:
	var out: List[Entry] = []
	var x = 7

	for i in 0..count:
		x = (x * 1103515245 + 12345) % 2147483648
		out.append(
			Entry(
				key: x % 10,
				id: i,
				name: "entry-name-longer-than-inline-{i}",
				tags: ["t{i}", "u"],
			)
		)

	return out

fn in_order(list: List[Entry]) Bool:
	for i in 1..list.length():
		before := list[i - 1]
		after := list[i]
		if before.key > after.key or (before.key == after.key and before.id > after.id):
			return false

	return true

test "sorting records that own strings and lists orders by key and keeps equal keys in input order":
	original := entries(500)
	sorted := original.sorted(compare: fn(a: Entry, b: Entry) Int: (a.key - b.key))
	expect_equal(in_order(sorted), true)?
	expect_equal(sorted.length(), 500)?
	expect_equal(in_order(original), false)?
	expect_equal(original[3].name, "entry-name-longer-than-inline-3")?

test "the sorted copy owns its strings and lists independently of the original":
	original := entries(100)
	var sorted = original.sorted(compare: fn(a: Entry, b: Entry) Int: b.key - a.key)
	sorted[0].tags.append("changed")
	sorted[0].name = "renamed"
	expect_equal(sorted[0].tags.length(), 3)?

	var seen = 0
	for e in original:
		if e.tags.length() != 2 or e.name == "renamed":
			seen += 1
	expect_equal(seen, 0)?

test "sorting records that own data in place keeps every record":
	var list = entries(300)
	list.sort(compare: fn(a: Entry, b: Entry) Int: a.key - b.key)
	expect_equal(in_order(list), true)?

	var ids = 0
	for e in list:
		ids += e.id
	expect_equal(ids, 299 * 300 / 2)?
	expect_equal(list[299].tags[1], "u")?
