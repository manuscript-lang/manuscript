// conform: tags=lists,maps,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `place[key] = value` consumes `key` at the store, after `value` ran, so `value` may read it.
type Bag {
	keys List[String]
	total Int = 0
}

fn var Bag.set(move key String, value Int) Void {
	self.total += value
	self.keys.append(key)
}

fn count_words(words List[String]) Map[String, Int] {
	var counts = Map[String, Int]()

	for w in words {
		key := w.clone()
		counts[key] = counts.get_or(key, 0) + 1
	}

	return counts
}

test "the value of a map store reads the key" {
	counts := count_words(["a", "b", "a"])
	expect_equal(counts.get_or("a", 0), 2)?
	expect_equal(counts.get_or("b", 0), 1)?
}

test "the key is read by a method of the value" {
	var sizes = Map[String, Int]()
	k := "four"
	sizes[k] = k.length()
	expect_equal(sizes.get_or("four", 0), 4)?
}

test "a user type stores its key after the value ran" {
	var bag = Bag(keys: [])
	key := "abc"
	bag[key] = key.length() * 2
	expect_equal(bag.total, 6)?
	expect_equal(bag.keys.length(), 1)?
}
