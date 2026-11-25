// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `get_or` on a map with a word value is answered by an inline probe: hits, misses, empty maps, colliding and long
// keys, and a default that differs from the stored value.
test "get_or on an Int-keyed map" {
	var m = Map[Int, Int]()
	expect_equal(m.get_or(1, 7), 7)?
	for i in 0..1000 {
		m[i * 3] = i
	}

	var total = 0
	for i in 0..3000 {
		total += m.get_or(i, -1)
	}
	expect_equal(total, 499500 + 2000 * -1)?
	expect_equal(m.get_or(3, 99), 1)?
	expect_equal(m.get_or(4, 99), 99)?
}

test "get_or on a String-keyed map counts words" {
	var m = Map[String, Int]()
	words := [
		"a", "bb", "a", "a-key-longer-than-fifteen-bytes", "bb",
		"a-key-longer-than-fifteen-bytes", "a"
	]
	for w in words {
		m[w] = m.get_or(w, 0) + 1
	}
	expect_equal(m.get_or("a", 0), 3)?
	expect_equal(m.get_or("bb", 0), 2)?
	expect_equal(m.get_or("a-key-longer-than-fifteen-bytes", 0), 2)?
	expect_equal(m.get_or("a-key-longer-than-fifteen-bytez", 5), 5)?
	expect_equal(m.get_or("", 4), 4)?
}

test "get_or on a Float-valued map" {
	var m = Map[String, Float]()
	m["pi"] = 3.5
	expect_equal(m.get_or("pi", 0.0), 3.5)?
	expect_equal(m.get_or("e", 2.25), 2.25)?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
