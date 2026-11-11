// conform: tags=strings,lists,maps,records,control-flow,stdlib-testing,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// Churn that reuses freed memory, so a view of a value freed too early reads garbage.
fn churn(n: Int) Int:
	var total = 0

	for i in 0..n:
		junk := "junk-{i}-junk-{i}-junk-{i}"
		total += junk.length()

	return total

test "a trim view keeps its source until the view's last use":
	source := "  hello, world  ".clone()
	view := source.trim()
	n := churn(200)
	expect_equal(view, "hello, world")?
	expect_equal(n > 0, true)?

test "a source whose last use is early is not needed by later work":
	text := "alpha beta gamma".clone()
	words := text.split(" ")
	count := words.length()
	n := churn(200)
	expect_equal(count, 3)?
	expect_equal(n > 0, true)?

test "a view carried around a loop stays valid":
	names := ["  a  ".clone(), " bb ".clone(), "ccc".clone()]
	var longest = ""
	var total = 0

	for name in names:
		view := name.trim()
		total += churn(20)
		if view.length() > longest.length():
			longest = view.clone()

	expect_equal(longest, "ccc")?
	expect_equal(total > 0, true)?

test "a value used only inside one branch is freed on the other path":
	data := [10, 20, 30]
	var sum = 0

	for i in 0..4:
		if i % 2 == 0:
			sum += data[0]
		else:
			sum += churn(5)

	expect_equal(sum > 20, true)?

test "map keys read after the map's earlier uses stay valid":
	var m = Map[String, Int]()
	m.add("one".clone(), 1)
	m.add("two".clone(), 2)

	size := m.length()
	var seen = 0
	for k in m.keys():
		seen += k.length()

	n := churn(100)
	expect_equal(size, 2)?
	expect_equal(seen, 6)?
	expect_equal(n > 0, true)?
