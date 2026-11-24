// conform: tags=maps,closures,scope-cleanup,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `Map.update` borrows its key: the caller keeps using it, and the map copies it only when the entry is new.
// The keys are longer than an inline String so a copy is a heap allocation.
test "a key stays usable after update, new or existing" {
	var counts Map[String, Int] = {}
	key := "a key that is longer than fifteen bytes"
	counts.update(key, 0, n => n + 1)
	counts.update(key, 0, n => n + 1)
	counts.update(key.clone(), 0, n => n + 1)
	expect_equal(counts.length(), 1)?
	expect_equal(counts[key], 3)?
	expect_equal(key.length(), 39)?
}

test "distinct long keys each get their own copy" {
	var counts Map[String, Int] = {}

	for round in 0..3 {
		for n in 0..4 {
			label := f"a label that is longer than inline {n}"
			counts.update(label, 10, v => v + round)
		}
	}

	expect_equal(counts.length(), 4)?
	expect_equal(counts["a label that is longer than inline 2"], 13)?
}
