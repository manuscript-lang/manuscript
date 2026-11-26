// conform: tags=testing,lists,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Item {
	name String
	tags List[String]
}

fn nested() List[List[String]] {
	return [["tmp", "b"]]
}

fn items() List[Item] {
	return [Item(name: "tmp", tags: ["x", "yy"])]
}

test "an immutable binding of a part of a temporary owns a copy" {
	n := nested()[0][1]
	expect_equal(n.length(), 1)?
}

test "a var binding of a part of a temporary owns a copy" {
	var s = nested()[0][0].clone()
	s += "!"
	expect_equal(s, "tmp!")?
}

test "a part two levels into a temporary record" {
	t := items()[0].tags[1]
	expect_equal(t, "yy")?
}

test "a list literal and append own copies of nested elements of a temporary" {
	a := [nested()[0][0].clone(), nested()[0][1].clone()]
	expect_equal(a.length(), 2)?

	var b List[String] = []
	b.append(nested()[0][1].clone())
	expect_equal(b[0], "b")?
}
// expect-exit: 0
// expect-tests: passed=4 failed=0
