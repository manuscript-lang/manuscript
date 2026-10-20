# conform: tags=aliasing,closures,control-flow,faults,generics,interfaces,lists,match,modules,mutation,optional,records,sets,stdlib-bytes,stdlib-regex,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/preferred-names.ms
import {expect_equal, expect_false} from "@std/testing.ms"
import Bytes from "@std/bytes.ms"
import {compile, Regex, RegexError} from "@std/regex.ms"

interface ListMutation:
    var fn reverse_in_place() Unit
    fn reversed() List[Int]
    var fn set(index: Int, value: Int) Unit
    var fn remove(index: Int) Unit
    var fn append(value: Int) Unit

type ListAdapter:
    items: List[Int]

impl ListMutation for ListAdapter:
    var fn reverse_in_place() Unit:
        self.items.reverse_in_place()

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
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int]
    ) Result[String, RegexError]

type RegexAdapter:
    pattern: Regex

impl RegexReplacement for RegexAdapter:
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int]
    ) Result[String, RegexError]:
        return self.pattern.replace_all(text, replacement, max_bytes)

fn add_generic[T: Hashable](var items: Set[T], value: T) Unit:
    items.add(value)

fn remove_generic[T: Hashable](var items: Set[T], value: T) Unit:
    items.remove(value)

test "list names mutate in place and retain shallow copies":
    var items = [1, 2, 3]
    let copied = items.clone()
    items.set(-1, 4)
    items.remove(0)
    try expect_false((items != [2, 4] or copied != [1, 2, 3]))
    let set = items.set
    let remove = items.remove
    set(value: 8, 0)
    remove(-1)
    remove(0)
    items.append(9)
    try expect_equal(items, [9])
    var optional: List[Optional[Int]] = [some(1)]
    optional.set(0, 7)
    try expect_equal(optional.get(0), some(7))
    var nested = [[1]]
    let outer_copy = nested.clone()
    nested.set(0, [2])
    try expect_false(nested != [[2]] or outer_copy != [[1]])

test "set names mutate in place keep order and no-op membership":
    var items = Set[Int]([3, 1, 2])
    let copied = items.clone()
    let add = items.add
    add(1)
    items.remove(99)
    try expect_equal(items.values(), [3, 1, 2])
    let remove = items.remove
    remove(1)
    items.add(1)
    items.remove(3)
    try expect_false(items.values() != [2, 1] or copied.values() != [3, 1, 2])
    add_generic(var items, 4)
    items.remove(2)
    remove_generic(var items, 1)
    items.add(5)
    try expect_equal(items.values(), [4, 5])
    var optional = Set[Optional[Int]]()
    optional.add(7)
    let optional_add = optional.add
    optional_add(9)
    optional.remove(7)
    try expect_equal(optional.values(), [some(9)])

interface FirstReplacement:
    fn replace_first(old: String, new: String, max_replacements: Optional[Int]) String

type TextAdapter:
    text: String

impl FirstReplacement for TextAdapter:
    fn replace_first(old: String, new: String, max_replacements: Optional[Int]) String:
        return self.text.replace_first(old, new, max_replacements)

test "explicit views and bound views preserve native mutation":
    var items = [1, 2, 3]
    var adapter = ListAdapter(items)
    adapter.set(0, 8)
    try expect_equal(adapter.items, [8, 2, 3])
    var view = ListMutation(adapter)
    view.set(0, 7)
    view.append(4)
    let view_set = view.set
    view_set(1, 9)
    view.remove(-1)
    let view_remove = view.remove
    view_remove(0)
    view.append(5)
    try expect_equal(view.reversed(), [5, 3, 9])
    var set = Set[Int]([1, 2])
    var set_view = SetMutation(SetAdapter(set))
    set_view.add(3)
    let view_add = set_view.add
    view_add(4)
    set_view.remove(1)
    let set_view_remove = set_view.remove
    set_view_remove(2)
    set_view.add(5)
    try expect_equal(set_view.values(), [3, 4, 5])
    let text_view = FirstReplacement(TextAdapter("aaaa"))
    let view_first = text_view.replace_first
    try expect_false(
        (
            text_view.replace_first("a", "b", none) != "baaa"
            or view_first("a", "b", 2) != "bbaa"
        )
    )

test "replace_first preserves first default explicit caps and scalar boundaries":
    try expect_equal("aaaa".replace_first("a", "b"), "baaa")
    try expect_equal("aaaa".replace_first("a", "b", none), "baaa")
    try expect_equal("aaaa".replace_first("a", "b", 0), "aaaa")
    try expect_equal("aaaa".replace_first("a", "b", 2), "bbaa")
    try expect_equal("aaaa".replace_first("a", "b", 9223372036854775807), "bbbb")
    try expect_equal("aa".replace_first("a", "aa", 2), "aaaa")
    try expect_equal("é🙂".replace_first("", "x", 2), "xéx🙂")
    try expect_equal("".replace_first("", "x"), "x")
    try expect_equal("abc".replace_first("z", "x"), "abc")
    let first = "aaaa".replace_first
    try expect_false(first(new: "b", "a") != "baaa" or first("a", "b", 2) != "bbaa")
    try expect_equal(first("a", "b"), "aaaa".replace("a", "b"))

test "regex replace_all preserves literal text and exact output budgets":
    let pattern = try compile("(a)")
    let all = pattern.replace_all
    try expect_equal((try pattern.replace_all("aaa", "b")), "bbb")
    try expect_equal((try all(replacement: "$1", "aa")), "$1$1")
    try expect_equal((try pattern.replace_all("aa", "é", 4)), "éé")
    let limited: Result[String, RegexError] = error(RegexError.LimitExceeded)
    let invalid: Result[String, RegexError] = error(RegexError.InvalidInput)
    try expect_equal(pattern.replace_all("aa", "é", 3), limited)
    try expect_equal(all("a", "", -1), invalid)
    try expect_equal((try all("a", "", 0)), "")
    try expect_equal(pattern.replace_all("z", "b", 0), limited)
    try expect_equal(
        pattern.replace_all("aa", "b", none),
        pattern.replace_all("aa", "b", none)
    )
    let empty = try compile("")
    try expect_equal((try empty.replace_all("é🙂", "x")), "xéx🙂x")
    let view = RegexReplacement(RegexAdapter(pattern))
    let view_all = view.replace_all
    try expect_false(
        (
            (try view.replace_all("aaa", "b", none)) != "bbb"
            or (try view_all("aa", "b", 2)) != "bb"
        )
    )

test "new direct keyed calls evaluate arguments after the receiver is chosen":
    var items = Set[Int]([1])
    items.add(
        match some(0):
            some(_): 2
            none: 3
    )
    try expect_equal(items.values(), [1, 2])
    items.remove(
        match some(0):
            some(_): 1
            none: 2
    )
    try expect_equal(items.values(), [2])

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
    let copied = items.reversed()
    let reverse = items.reverse_in_place
    reverse()
    items.append(4)
    try expect_false((items != [3, 2, 1, 4] or copied != [3, 2, 1]))
    var changed = copied.clone()
    changed.set(0, 8)
    let reversed = items.reversed
    var detached = reversed()
    detached.remove(0)
    try expect_equal(items, [3, 2, 1, 4])
    items.reverse_in_place()
    items.reverse_in_place()
    try expect_equal(items, [3, 2, 1, 4])
    var empty: List[Int] = []
    empty.reverse_in_place()
    var flipped = empty.reversed()
    flipped.append(1)
    try expect_false(not empty.is_empty())
    let one = [1]
    var one_flipped = one.reversed()
    one_flipped.set(0, 2)
    try expect_equal(one, [1])
    let nested = [Cell(1), Cell(2)]
    var shallow = nested.reversed()
    shallow.set(1, Cell(7))
    try expect_false(nested.get(0).value != 1 or nested.get(1).value != 2)
    var viewed = ListAdapter([4, 5])
    var view = ListMutation(viewed)
    var other = view.reversed()
    other.append(6)
    view.reverse_in_place()
    let view_reversed = view.reversed
    var view_copy = view_reversed()
    view_copy.set(0, 7)
    let view_reverse = view.reverse_in_place
    view_reverse()
    try expect_equal(view.reversed(), [5, 4])

test "byte reversal names copy across direct bound and view calls":
    let data = Bytes([0, 1, 255])
    let reversed = data.reversed
    let view = ByteCopy(ByteAdapter(data.clone()))
    let view_reversed = view.reversed
    try expect_false(
        (data.reversed() != Bytes([255, 1, 0]) or reversed() != data.reversed())
    )
    try expect_false(
        (
            view.reversed() != data.reversed()
            or view_reversed() != data.reversed()
        )
    )
    var extracted = reversed().values()
    extracted.set(0, 7)
    try expect_false(data != Bytes([0, 1, 255]) or reversed() != Bytes([255, 1, 0]))
    try expect_false(
        (
            Bytes([]).reversed().length() != 0
            or Bytes([1]).reversed() != Bytes([1])
        )
    )
