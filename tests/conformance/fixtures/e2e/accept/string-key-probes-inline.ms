// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

// `contains` and `get` on a map or set of strings run in line: inline keys, long keys, keys with
// multibyte scalars, and absent keys all answer as the runtime does.
test "string keys of every size are found and missing ones are not" {
	var m = Map[String, Int]()
	var s = Set[String]()

	for i in 0..300 {
		m.add("key number " + i.to_string() + " padded to be long enough", i)
		m.add("k" + i.to_string(), i * 2)
		m.add("é" + i.to_string(), i * 3)
		s.add("s" + i.to_string())
	}

	var hits = 0
	var sum = 0

	for i in 0..400 {
		if m.contains("k" + i.to_string()) {
			hits += 1
		}
		if m.contains("key number " + i.to_string() + " padded to be long enough") {
			hits += 1
		}
		if m.contains("é" + i.to_string()) {
			hits += 1
		}
		if s.contains("s" + i.to_string()) {
			hits += 1
		}
		sum += m.get_or("k" + i.to_string(), 7)

		v := m.get("é" + i.to_string())
		if v != null {
			sum += v
		}
	}

	expect_equal(hits, 1200)?
	expect_equal(sum, 224950)?
}
