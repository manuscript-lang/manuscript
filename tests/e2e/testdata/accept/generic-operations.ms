import expect_equal from "@std/test/test.ms"

type Bag:
	items: List[Int]

interface Picker[T]:
	fn pick[K: Comparable](key: fn(T) K) T?
	fn mapped[U](transform: fn(T) U) List[U]

impl Picker[Int] for Bag:
	fn pick[K: Comparable](key: fn(Int) K) Int?:
		if self.items.is_empty(): return none

		var at = 0
		var best = key(self.items[0])

		for i in 1..self.items.length():
			k := key(self.items[i])

			if k.compare(best) > 0:
				at = i
				best = k

		return self.items[at]

	fn mapped[U](transform: fn(Int) U) List[U]:
		var out = self.items.map(fn x: transform(x))
		return out

impl Bag:
	fn paired[U: Clonable](other: U) List[U]:
		var out = self.items.map(fn item: other.clone())
		return out

fn pick_with[B: Picker[Int]](bag: B) Int?:
	return bag.pick(fn(x: Int) Int: 0 - x)

test "an interface operation takes type parameters of its own":
	bag := Bag(items: [3, 1, 2])
	bag.pick(fn(x: Int) Int: x) | expect_equal(3)?
	bag.pick(fn(x: Int) String: "\{x\}") | expect_equal(3)?
	bag.mapped(fn(x: Int) String: "n") | expect_equal(["n", "n", "n"])?

test "a bounded type parameter calls a generic operation":
	pick_with(Bag(items: [3, 1, 2])) | expect_equal(1)?

test "an inherent method takes type parameters of its own":
	Bag(items: [1, 2]).paired("a") | expect_equal(["a", "a"])?
	Bag(items: [1, 2]).paired(true) | expect_equal([true, true])?

test "List max_by and min_by are source methods":
	words := ["bb", "a", "ccc", "dd"]
	words.max_by(fn(w: String) Int: w.length()) | expect_equal("ccc")?
	words.min_by(fn(w: String) Int: w.length()) | expect_equal("a")?

fn main() Unit:
	return
