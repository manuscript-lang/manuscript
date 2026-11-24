// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Named:
	name: String

test "optional string keys hash and compare":
	var m = Map[String?, Int]()
	m.add("x", 1)
	m.add("x", 2)
	m.add(null, 3)
	m.add(null, 4)
	m.add("", 5)
	expect_equal(m.length(), 3)?
	expect_equal(m.get_or("x", 0), 2)?
	expect_equal(m.get_or(null, 0), 4)?
	expect_equal(m.get_or("", 0), 5)?

test "optional record keys in a set":
	var s = Set[Named?]()
	s.add(Named("a"))
	s.add(Named("a"))
	s.add(null)
	s.add(null)
	expect_equal(s.length(), 2)?
	expect_equal(s.contains(Named("a")), true)?
	expect_equal(s.contains(Named("b")), false)?
