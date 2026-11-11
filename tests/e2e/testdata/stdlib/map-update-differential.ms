import expect_equal from "@std/test/test.ms"

// A key whose `clone` is source-defined.
type Tag:
	name: String

fn Tag.clone() Tag:
	return Tag(name: self.name.clone())

impl Equal for Tag:
	fn equals(other: Tag) Bool:
		return self.name == other.name

impl Hashable for Tag:
	fn hash() Int:
		return self.name.hash()

fn append_length(xs: List[Int]) List[Int]:
	var out = xs.clone()
	out.append(xs.length())
	return out

// Each pair below spells one update twice: `Map.update`, which looks the key up once,
// and the
// `get_or` plus `add` pair, which looks it up twice. The maps must stay equal after every step.

test "update matches get_or and add for String keys":
	words := ["a", "bb", "a", "ccc", "bb", "a", "", "ccc", ""]
	var once: Map[String, Int] = {}
	var twice: Map[String, Int] = {}

	for index in 0..words.length():
		w := words[index]
		once.update(w.clone(), 1, fn v: v * 2 - index)
		twice.add(w.clone(), twice.get_or(w, 1) * 2 - index)

	expect_equal(once.length(), twice.length())?
	for word in ["a", "bb", "ccc", ""]:
		expect_equal(once.get(word), twice.get(word))?

test "update matches get_or and add for Int keys and Float values":
	var once: Map[Int, Float] = {}
	var twice: Map[Int, Float] = {}

	for key in [3, 1, 3, 2, 1, 3]:
		once.update(key, 0.5, fn v: v * 3.0)
		twice.add(key, twice.get_or(key, 0.5) * 3.0)

	for key in [1, 2, 3, 4]:
		expect_equal(once.get(key), twice.get(key))?

test "update matches get_or and add for source-defined key types":
	var once: Map[Tag, Int] = {}
	var twice: Map[Tag, Int] = {}

	for name in ["x", "y", "x", "x", "z", "y"]:
		once.update(Tag(name: name.clone()), 0, fn v: v + 1)
		twice.add(Tag(name: name.clone()), twice.get_or(Tag(name: name.clone()), 0) + 1)

	expect_equal(once.length(), twice.length())?

	for name in ["x", "y", "z", "w"]:
		tag := Tag(name: name)
		expect_equal(once.get(tag), twice.get(tag))?

test "update replaces owned values and keeps insertion order":
	var once: Map[String, List[Int]] = {}
	for name in ["b", "a", "b", "b", "a"]:
		once.update(name.clone(), [], append_length)
	expect_equal(once.keys(), ["b", "a"])?
	expect_equal(once.get("b"), [0, 1, 2])?
	expect_equal(once.get("a"), [0, 1])?

test "update evaluates initial eagerly and drops it when the key exists":
	var once: Map[Int, String] = {1: "x"}
	once.update(1, "unused", fn v: v + "y")
	once.update(2, "new", fn v: v + "y")
	expect_equal(once.get(1), "xy")?
	expect_equal(once.get(2), "newy")?
