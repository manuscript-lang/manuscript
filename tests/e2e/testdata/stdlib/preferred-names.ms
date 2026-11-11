import (
	Bytes from "@std/bytes.ms",
	Regex, compile from "@std/string.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

interface ListMutation:
	var fn reverse() Unit
	fn reversed() List[Int]
	var fn set(index: Int, value: Int) Unit
	var fn remove(index: Int) Unit
	var fn append(value: Int) Unit

type ListAdapter:
	items: List[Int]

impl ListMutation for ListAdapter:
	var fn reverse() Unit:
		self.items.reverse()

	fn reversed() List[Int]:
		return self.items.reversed()

	var fn set(index: Int, value: Int) Unit:
		self.items.set(index, value)

	var fn remove(index: Int) Unit:
		self.items.remove(index)

	var fn append(value: Int) Unit:
		self.items.append(value)

interface SetMutation:
	var fn add(value: Int) Unit
	var fn remove(value: Int) Unit
	fn values() List[Int]

type SetAdapter:
	items: Set[Int]

impl SetMutation for SetAdapter:
	var fn add(value: Int) Unit:
		self.items.add(value)

	var fn remove(value: Int) Unit:
		self.items.remove(value)

	fn values() List[Int]:
		return self.items.values()

interface RegexReplacement:
	fn replace_all(text: String, replacement: String, max_bytes: Int?) String!

type RegexAdapter:
	pattern: Regex

impl RegexReplacement for RegexAdapter:
	fn replace_all(text: String, replacement: String, max_bytes: Int?) String!:
		return self.pattern.replace_all(text, replacement, max_bytes)

fn add_generic[T: Hashable](var items: Set[T], value: T) Unit:
	items.add(value)

fn remove_generic[T: Hashable](var items: Set[T], value: T) Unit:
	items.remove(value)

test "list names mutate in place and retain shallow copies":
	var items = [1, 2, 3]
	copied := items.clone()
	items.set(-1, 4)
	items.remove(0)
	expect_false((items != [2, 4] or copied != [1, 2, 3]))?
	items.set(0, value: 8)
	items.remove(-1)
	items.remove(0)
	items.append(9)
	expect_equal(items, [9])?

	var optional: List[Int?] = [1]
	optional.set(0, 7)
	expect_equal(optional.get(0), 7)?

	var nested = [[1]]
	outer_copy := nested.clone()
	nested.set(0, [2])
	expect_false(nested != [[2]] or outer_copy != [[1]])?

test "set names mutate in place keep order and no-op membership":
	var items = Set[Int]([3, 1, 2])
	copied := items.clone()
	items.add(1)
	items.remove(99)
	expect_equal(items.values(), [3, 1, 2])?
	items.remove(1)
	items.add(1)
	items.remove(3)
	expect_false(items.values() != [2, 1] or copied.values() != [3, 1, 2])?
	add_generic(var items, 4)
	items.remove(2)
	remove_generic(var items, 1)
	items.add(5)
	expect_equal(items.values(), [4, 5])?

	var optional = Set[Int?]()
	optional.add(7)
	optional.add(9)
	optional.remove(7)

	expected_values: List[Int?] := [9]
	expect_equal(optional.values(), expected_values)?

interface FirstReplacement:
	fn replace_first(old: String, new: String) String

type TextAdapter:
	text: String

impl FirstReplacement for TextAdapter:
	fn replace_first(old: String, new: String) String:
		return self.text.replace_first(old, new)

test "explicit views and bound views preserve native mutation":
	var items = [1, 2, 3]
	var adapter = ListAdapter(items)
	adapter.set(0, 8)
	expect_equal(adapter.items, [8, 2, 3])?

	var view: ListMutation = adapter
	view.set(0, 7)
	view.append(4)
	view.set(1, 9)
	view.remove(-1)
	view.remove(0)
	view.append(5)
	expect_equal(view.reversed(), [5, 3, 9])?

	var set = Set[Int]([1, 2])
	var set_view: SetMutation = SetAdapter(set)
	set_view.add(3)
	set_view.add(4)
	set_view.remove(1)
	set_view.remove(2)
	set_view.add(5)
	expect_equal(set_view.values(), [3, 4, 5])?

	text_view: FirstReplacement := TextAdapter("aaaa")
	view_first := text_view.replace_first
	expect_false(
		text_view.replace_first("a", "b") != "baaa" or view_first(
			"a",
			"b",
		) != "baaa"
	)?

test "replace_first changes one match and scalar boundaries":
	expect_equal("aaaa".replace_first("a", "b"), "baaa")?
	expect_equal("é🙂".replace_first("", "x"), "xé🙂")?
	expect_equal("".replace_first("", "x"), "x")?
	expect_equal("abc".replace_first("z", "x"), "abc")?

	first := "aaaa".replace_first
	expect_false(first(new: "b", "a") != "baaa")?
	expect_equal(first("a", "b"), "aaaa".replace_first("a", "b"))?

test "regex replace_all preserves literal text and exact output budgets":
	pattern := compile("(a)")?
	all := pattern.replace_all
	expect_equal((pattern.replace_all("aaa", "b")?), "bbb")?
	expect_equal((all(replacement: "$1", "aa")?), "$1$1")?
	expect_equal((pattern.replace_all("aa", "é", 4)?), "éé")?

	limited: String! := error(
		Error("regular expression: limit exceeded", kind: "EOVERFLOW")
	)
	invalid: String! := error(
		Error("regular expression: invalid input", kind: "EINVAL")
	)
	expect_equal(pattern.replace_all("aa", "é", 3), limited)?
	expect_equal(all("a", "", -1), invalid)?
	expect_equal((all("a", "", 0)?), "")?
	expect_equal(pattern.replace_all("z", "b", 0), limited)?
	expect_equal(
		pattern.replace_all("aa", "b", none),
		pattern.replace_all("aa", "b", none),
	)?

	empty := compile("")?
	expect_equal((empty.replace_all("é🙂", "x")?), "xéx🙂x")?

	view: RegexReplacement := RegexAdapter(pattern)
	view_all := view.replace_all
	expect_false(
		(
			(view.replace_all("aaa", "b", none)?) != "bbb"
			or (view_all("aa", "b", 2)?) != "bb"
		)
	)?

test "new direct keyed calls evaluate arguments after the receiver is chosen":
	var items = Set[Int]([1])
	items.add(
		match present(0):
			_value: 2
			none: 3
	)
	expect_equal(items.values(), [1, 2])?
	items.remove(
		match present(0):
			_value: 1
			none: 2
	)
	expect_equal(items.values(), [2])?

type Cell:
	value: Int

interface ByteCopy:
	fn reversed() Bytes

type ByteAdapter:
	data: Bytes

impl ByteCopy for ByteAdapter:
	fn reversed() Bytes:
		return self.data.reversed()

test "list reversal names distinguish receiver mutation and shallow copies":
	var items = [1, 2, 3]
	copied := items.reversed()
	items.reverse()
	items.append(4)
	expect_false((items != [3, 2, 1, 4] or copied != [3, 2, 1]))?

	var changed = copied.clone()
	changed.set(0, 8)

	reversed := items.reversed
	var detached = reversed()
	detached.remove(0)
	expect_equal(items, [3, 2, 1, 4])?
	items.reverse()
	items.reverse()
	expect_equal(items, [3, 2, 1, 4])?

	var empty: List[Int] = []
	empty.reverse()

	var flipped = empty.reversed()
	flipped.append(1)
	expect_false(not empty.is_empty())?

	one := [1]
	var one_flipped = one.reversed()
	one_flipped.set(0, 2)
	expect_equal(one, [1])?

	nested := [Cell(1), Cell(2)]
	var shallow = nested.reversed()
	shallow.set(1, Cell(7))
	expect_false(nested.get(0).value != 1 or nested.get(1).value != 2)?

	var viewed = ListAdapter([4, 5])
	var view: ListMutation = viewed
	var other = view.reversed()
	other.append(6)
	view.reverse()

	view_reversed := view.reversed
	var view_copy = view_reversed()
	view_copy.set(0, 7)
	view.reverse()
	expect_equal(view.reversed(), [5, 4])?

test "byte reversal names copy across direct bound and view calls":
	data := Bytes([0, 1, 255])
	reversed := data.reversed
	view: ByteCopy := ByteAdapter(data.clone())
	view_reversed := view.reversed
	expect_false(
		(data.reversed() != Bytes([255, 1, 0]) or reversed() != data.reversed())
	)?
	expect_false(
		(
			view.reversed() != data.reversed()
			or view_reversed() != data.reversed()
		)
	)?

	var extracted = reversed().values()
	extracted.set(0, 7)
	expect_false(data != Bytes([0, 1, 255]) or reversed() != Bytes([255, 1, 0]))?
	expect_false(
		(
			not Bytes([]).reversed().is_empty()
			or Bytes([1]).reversed() != Bytes([1])
		)
	)?

fn present[T](value: T) T?:
	return value
