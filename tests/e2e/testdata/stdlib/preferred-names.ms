import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import Bytes from "@std/bytes.ms"
import {compile, Regex, RegexError} from "@std/regex.ms"

interface ListMutation:
    fn reverse_in_place() -> List[Int]
    fn reversed() -> List[Int]
    fn set(index: Int, value: Int) -> List[Int]
    fn remove(index: Int) -> List[Int]

type ListAdapter:
    items: List[Int]
    set: fn(index: Int, value: Int) -> List[Int]

impl ListMutation for ListAdapter:
    fn reverse_in_place() -> List[Int]:
        return self.items.reverse_in_place()

    fn reversed() -> List[Int]:
        return self.items.reversed()

    fn set(index: Int, value: Int) -> List[Int]:
        return self.items.set(index, value)

    fn remove(index: Int) -> List[Int]:
        return self.items.remove(index)

interface SetMutation:
    fn add(value: Int) -> Set[Int]
    fn remove(value: Int) -> Set[Int]

type SetAdapter:
    items: Set[Int]

impl SetMutation for SetAdapter:
    fn add(value: Int) -> Set[Int]:
        return self.items.add(value)

    fn remove(value: Int) -> Set[Int]:
        return self.items.remove(value)

interface RegexReplacement:
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int]
    ) -> Result[String, RegexError]

type RegexAdapter:
    pattern: Regex

impl RegexReplacement for RegexAdapter:
    fn replace_all(
        text: String,
        replacement: String,
        max_bytes: Optional[Int]
    ) -> Result[String, RegexError]:
        return self.pattern.replace_all(text, replacement, max_bytes)

fn add_generic[T: Hashable](items: Set[T], value: T) -> Set[T]:
    return items.add(value)

fn remove_generic[T: Hashable](items: Set[T], value: T) -> Set[T]:
    return items.remove(value)

test "list names mutate aliases and retain shallow copies":
    let items = [1, 2, 3]
    let alias = items
    let copied = items.clone()
    let returned = items.set(index: -1, value: 4)
    returned.remove(index: 0)
    (items != [2, 4] or alias != [2, 4] or copied != [1, 2, 3]) | try expect_false
    let set = items.set
    let remove = items.remove
    set(value: 8, index: 0).remove(-1)
    remove(0).append(9)
    items | try expect_equal(expected: [9])
    let optional: List[Optional[Int]] = [some(1)]
    optional.set(0, 7)
    optional.at(0).unwrap() | try expect_equal(expected: some(7))
    let nested = [[1]]
    let outer_copy = nested.clone()
    nested.set(0, [2])
    outer_copy.at(0).unwrap().append(3)
    (nested != [[2]] or outer_copy != [[1, 3]]) | try expect_false

test "set names preserve receiver identity order and no-op membership":
    let items = Set[Int]().add(3).add(1).add(2)
    let alias = items
    let copied = items.clone()
    let add = items.add
    let remove = items.remove
    add(1).remove(99)
    items.values() | try expect_equal(expected: [3, 1, 2])
    remove(1).add(1).remove(3)
    (alias.values() != [2, 1] or copied.values() != [3, 1, 2]) | try expect_false
    add_generic(items, 4).remove(2)
    remove_generic(items, 1).add(5)
    items.values() | try expect_equal(expected: [4, 5])
    let optional = Set[Optional[Int]]().add(7)
    let optional_add = optional.add
    optional_add(9)
    optional.remove(7)
    optional.values() | try expect_equal(expected: [some(9)])

interface FirstReplacement:
    fn replace_first(
        old: String,
        new: String,
        max_replacements: Optional[Int]
    ) -> String

type TextAdapter:
    text: String

impl FirstReplacement for TextAdapter:
    fn replace_first(
        old: String,
        new: String,
        max_replacements: Optional[Int]
    ) -> String:
        return self.text.replace_first(old, new, max_replacements)

test "explicit views and bound views preserve native mutation and field shadowing":
    let items = [1, 2, 3]
    let adapter = ListAdapter(items, fn(index: Int, value: Int) -> List[Int]: [99])
    (adapter.set(0, 8) != [99] or items != [1, 2, 3]) | try expect_false
    let view = ListMutation(adapter)
    let view_set = view.set
    let view_remove = view.remove
    view.set(0, 8).append(4)
    view_set(1, 9)
    view.remove(-1)
    view_remove(0).append(5)
    items | try expect_equal(expected: [9, 3, 5])
    let set = Set[Int]().add(1).add(2)
    let set_view = SetMutation(SetAdapter(set))
    let view_add = set_view.add
    let set_view_remove = set_view.remove
    set_view.add(3)
    view_add(4)
    set_view.remove(1)
    set_view_remove(2).add(5)
    set.values() | try expect_equal(expected: [3, 4, 5])
    let text_view = FirstReplacement(TextAdapter("aaaa"))
    let view_first = text_view.replace_first
    try expect_false(
        (
            text_view.replace_first("a", "b", none) != "baaa"
            or view_first("a", "b", 2) != "bbaa"
        )
    )

test "replace_first preserves first default explicit caps and scalar boundaries":
    "aaaa".replace_first(old: "a", new: "b") | try expect_equal(expected: "baaa")
    "aaaa".replace_first("a", "b", none) | try expect_equal(expected: "baaa")
    "aaaa".replace_first("a", "b", 0) | try expect_equal(expected: "aaaa")
    "aaaa".replace_first("a", "b", 2) | try expect_equal(expected: "bbaa")
    "aaaa".replace_first("a", "b", 9223372036854775807) | try expect_equal(
        expected: "bbbb"
    )
    "aa".replace_first("a", "aa", 2) | try expect_equal(expected: "aaaa")
    "é🙂".replace_first("", "x", 2) | try expect_equal(expected: "xéx🙂")
    "".replace_first("", "x") | try expect_equal(expected: "x")
    "abc".replace_first("z", "x") | try expect_equal(expected: "abc")
    let first = "aaaa".replace_first
    (first(new: "b", old: "a") != "baaa" or first("a", "b", 2) != "bbaa") | try expect_false
    first("a", "b") | try expect_equal(expected: "aaaa".replace("a", "b"))

test "regex replace_all preserves literal text and exact output budgets":
    let pattern = (compile("(a)") | try expect_ok)
    let all = pattern.replace_all
    pattern.replace_all("aaa", "b") | try expect_ok | try expect_equal(expected: "bbb")
    all(replacement: "$1", text: "aa") | try expect_ok | try expect_equal(
        expected: "$1$1"
    )
    pattern.replace_all("aa", "é", 4) | try expect_ok | try expect_equal(expected: "éé")
    let limited: Result[String, RegexError] = error(RegexError.LimitExceeded)
    let invalid: Result[String, RegexError] = error(RegexError.InvalidInput)
    pattern.replace_all("aa", "é", 3) | try expect_equal(expected: limited)
    all("a", "", -1) | try expect_equal(expected: invalid)
    all("a", "", 0) | try expect_ok | try expect_equal(expected: "")
    pattern.replace_all("z", "b", 0) | try expect_equal(expected: limited)
    pattern.replace_all("aa", "b", none) | try expect_equal(
        expected: pattern.replace_all("aa", "b", none)
    )
    let empty = (compile("") | try expect_ok)
    empty.replace_all("é🙂", "x") | try expect_ok | try expect_equal(expected: "xéx🙂x")
    let view = RegexReplacement(RegexAdapter(pattern))
    let view_all = view.replace_all
    try expect_false(
        (
            (view.replace_all("aaa", "b", none) | try expect_ok) != "bbb"
            or (view_all("aa", "b", 2) | try expect_ok) != "bb"
        )
    )

test "new direct keyed calls capture receivers before arguments":
    var items = Set[Int]().add(1)
    let original = items
    let result = items.add(
        match some(0):
            some(_):
                items = Set[Int]().add(8)
                2
            none: 3
    )
    try expect_false(
        (
            result.values() != [1, 2]
            or original.values() != [1, 2]
            or items.values() != [8]
        )
    )
    result.remove(
        match some(0):
            some(_):
                items = Set[Int]().add(9)
                1
            none: 2
    )
    (result.values() != [2] or items.values() != [9]) | try expect_false

type Cell:
    value: Int

interface ByteCopy:
    fn reversed() -> Bytes

type ByteAdapter:
    data: Bytes

impl ByteCopy for ByteAdapter:
    fn reversed() -> Bytes:
        return self.data.reversed()

test "list reversal names distinguish receiver mutation and shallow copies":
    let items = [1, 2, 3]
    let alias = items
    let copied = items.reversed()
    let reverse = items.reverse_in_place
    reverse().append(4)
    (items != [3, 2, 1, 4] or alias != [3, 2, 1, 4] or copied != [3, 2, 1]) | try expect_false
    copied.set(0, 8)
    let reversed = items.reversed
    reversed().remove(0)
    items | try expect_equal(expected: [3, 2, 1, 4])
    items.reverse_in_place().reverse_in_place()
    items | try expect_equal(expected: [3, 2, 1, 4])
    let empty: List[Int] = []
    empty.reverse_in_place().reversed().append(1)
    (empty.is_empty()) | try expect_true
    let one = [1]
    one.reversed().set(0, 2)
    one | try expect_equal(expected: [1])
    let nested = [Cell(1), Cell(2)]
    let shallow = nested.reversed()
    let shared = shallow.at(0).unwrap()
    shared.value = 9
    shallow.set(1, Cell(7))
    (nested.at(0).unwrap().value != 1 or nested.at(1).unwrap().value != 9) | try expect_false
    let viewed = [4, 5]
    let adapter = ListAdapter(viewed, fn(index: Int, value: Int) -> List[Int]: [99])
    let view = ListMutation(adapter)
    let view_reverse = view.reverse_in_place
    let view_reversed = view.reversed
    view.reversed().append(6)
    view.reverse_in_place()
    view_reversed().set(0, 7)
    view_reverse()
    viewed | try expect_equal(expected: [4, 5])

test "byte reversal names copy across direct bound and view calls":
    let data = Bytes([0, 1, 255])
    let reversed = data.reversed
    let view = ByteCopy(ByteAdapter(data))
    let view_reversed = view.reversed
    (data.reversed() != Bytes([255, 1, 0]) or reversed() != data.reversed()) | try expect_false
    try expect_false(
        (
            view.reversed() != data.reversed()
            or view_reversed() != data.reversed()
        )
    )
    let extracted = reversed().values()
    extracted.set(0, 7)
    (data != Bytes([0, 1, 255]) or reversed() != Bytes([255, 1, 0])) | try expect_false
    try expect_false(
        (
            Bytes([]).reversed().length() != 0
            or Bytes([1]).reversed() != Bytes([1])
        )
    )
