// conform: tags=closures,lists,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Order:
	id Int
	status String
	items List[String]

fn orders() List[Order]:
	return [
		Order(1, "placed", ["a", "b"]),
		Order(2, "shipped", ["c"]),
		Order(3, "placed", []),
		Order(4, "cancelled", ["d", "e", "f"]),
		Order(5, "placed", ["g"]),
	]

fn placed_ids(os List[Order]) List[Int]:
	var ids List[Int] = []
	for o in os.filter(fn o: o.status == "placed"):
		ids.append(o.id)
	return ids

test "a filtered loop visits the kept elements in order":
	expect_equal(placed_ids(orders()), [1, 3, 5])?

test "two filters, a captured value, break and continue":
	os := orders()
	want := "placed"
	var seen List[Int] = []
	for o in os.filter(fn o: o.status == want).filter(fn o: o.id > 1):
		seen.append(o.id)
	expect_equal(seen, [3, 5])?

	var first List[Int] = []

	for o in os.filter(fn o: o.status != "shipped"):
		if o.id == 3: continue
		if o.id == 5: break

		first.append(o.id)

	expect_equal(first, [1, 4])?

fn first_with_items(os List[Order]) Int:
	for o in os.filter(fn o: not o.items.is_empty()):
		if o.id > 3: return o.id
	return -1

test "return from inside a filtered loop":
	expect_equal(first_with_items(orders()), 4)?

test "nothing kept and an empty list":
	os := orders()
	var n = 0
	for o in os.filter(fn o: o.status == "none"):
		n += o.id

	null List[Order] := []
	for o in null.filter(fn o: o.id > 0):
		n += 100
	expect_equal(n, 0)?

test "an element property that is not a record":
	words := ["pear", "fig", "apple", "kiwi"]
	var out List[String] = []
	for w in words.filter(fn w: w != "fig"):
		out.append(w.upper())
	expect_equal(out, ["PEAR", "APPLE", "KIWI"])?
