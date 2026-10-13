import {List, Set} from "@std/collections.ms"
import {compile, Regex, RegexError} from "@std/regex.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

interface ListMutation:
    fn set(index: Int, value: Int) -> List[Int]
    fn remove(index: Int) -> List[Int]

type ListAdapter:
    items: List[Int]
    set: fn(index: Int, value: Int) -> List[Int]

impl ListMutation for ListAdapter:
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
    if (
        items != [2, 4]
        or alias != [2, 4]
        or copied != [1, 2, 3]
    ):
        return panic("list alias or clone behavior")

    let set = items.set
    let remove = items.remove
    set(value: 8, index: 0).without(-1)
    remove(0).append(9)
    if items != [9]: return panic("bound list receiver return")

    let optional: List[Optional[Int]] = [some(1)]
    optional.set(0, 7)
    if optional.at(0).unwrap() != some(7): return panic("list Optional conversion")

    let nested = [[1]]
    let outer_copy = nested.clone()
    nested.set(0, [2])
    outer_copy.at(0).unwrap().append(3)
    if nested != [[2]] or outer_copy != [[1, 3]]: return panic("outer storage")

test "list mutators preserve membership snapshots":
    let items = [1, 2, 3]
    let visited: List[Int] = []

    for item in items:
        visited.append(item)
        items.set(0, 9)
        items.remove(-1)

    if visited != [1, 2, 3] or not items.is_empty(): return panic("loop snapshot")

    let callback_items = [1, 2, 3]
    let callback_visited: List[Int] = []
    callback_items.for_each(
        fn(item):
            callback_visited.append(item)
            callback_items.set(0, 9)
            callback_items.remove(-1)
    )
    if callback_visited != [1, 2, 3] or not callback_items.is_empty():
        return panic("callback snapshot")

test "set names preserve receiver identity order and no-op membership":
    let items = Set[Int]().add(3).with_value(1).add(2)
    let alias = items
    let copied = items.clone()
    let add = items.add
    let remove = items.remove
    add(1).remove(99)
    if items.values() != [3, 1, 2]: return panic("duplicate or absent membership")

    remove(1).add(1).without(3)
    if alias.values() != [2, 1] or copied.values() != [3, 1, 2]:
        return panic("set order or clone")

    add_generic(items, 4).remove(2)
    remove_generic(items, 1).with_value(5)
    if items.values() != [4, 5]: return panic("generic receiver return")

    let optional = Set[Optional[Int]]().add(7)
    let optional_add = optional.add
    optional_add(9)
    optional.remove(7)
    if optional.values() != [some(9)]: return panic("set Optional conversion")

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
    let adapter = ListAdapter(
        items,
        fn(index: Int, value: Int) -> List[Int]: [99]
    )
    if adapter.set(0, 8) != [99] or items != [1, 2, 3]:
        return panic("callable field shadowing")

    let view = ListMutation(adapter)
    let view_set = view.set
    let view_remove = view.remove
    view.set(0, 8).append(4)
    view_set(1, 9)
    view.remove(-1)
    view_remove(0).append(5)
    if items != [9, 3, 5]: return panic("List view mutation or bound receiver")

    let set = Set[Int]().add(1).add(2)
    let set_view = SetMutation(SetAdapter(set))
    let view_add = set_view.add
    let set_view_remove = set_view.remove
    set_view.add(3)
    view_add(4)
    set_view.remove(1)
    set_view_remove(2).add(5)
    if set.values() != [3, 4, 5]: return panic("Set view mutation or order")

    let text_view = FirstReplacement(TextAdapter("aaaa"))
    let view_first = text_view.replace_first
    if (
        text_view.replace_first("a", "b", none) != "baaa"
        or view_first("a", "b", 2) != "bbaa"
    ):
        return panic("String view replacement")

test "replace_first preserves first default explicit caps and scalar boundaries":
    if "aaaa".replace_first(old: "a", new: "b") != "baaa": return panic("first default")
    if "aaaa".replace_first("a", "b", none) != "baaa": return panic("first none")
    if "aaaa".replace_first("a", "b", 0) != "aaaa": return panic("zero cap")
    if "aaaa".replace_first("a", "b", 2) != "bbaa": return panic("explicit cap")
    if "aaaa".replace_first("a", "b", 9223372036854775807) != "bbbb":
        return panic("large cap")
    if "aa".replace_first("a", "aa", 2) != "aaaa": return panic(
        "inserted text rescanned"
    )
    if "é🙂".replace_first("", "x", 2) != "xéx🙂": return panic("scalar boundaries")
    if "".replace_first("", "x") != "x": return panic("empty text")
    if "abc".replace_first("z", "x") != "abc": return panic("no match")

    let first = "aaaa".replace_first
    if first(new: "b", old: "a") != "baaa" or first("a", "b", 2) != "bbaa":
        return panic("bound defaults or reordered labels")
    if first("a", "b") != "aaaa".replace("a", "b"): return panic("old replace spelling")

test "regex replace_all preserves literal text and exact output budgets":
    let pattern = value(compile("(a)"))
    let all = pattern.replace_all
    if value(pattern.replace_all("aaa", "b")) != "bbb": return panic("all matches")
    if value(all(replacement: "$1", text: "aa")) != "$1$1": return panic(
        "capture expansion"
    )
    if value(pattern.replace_all("aa", "é", 4)) != "éé": return panic("UTF8 boundary")

    let limited: Result[String, RegexError] = error(RegexError.LimitExceeded)
    let invalid: Result[String, RegexError] = error(RegexError.InvalidInput)
    if pattern.replace_all("aa", "é", 3) != limited: return panic("output budget")
    if all("a", "", -1) != invalid: return panic("negative budget")
    if value(all("a", "", 0)) != "": return panic("empty output budget")
    if pattern.replace_all("z", "b", 0) != limited: return panic(
        "unchanged output budget"
    )
    if pattern.replace_all("aa", "b", none) != pattern.replace("aa", "b", none):
        return panic("old regex spelling")

    let empty = value(compile(""))
    if value(empty.replace_all("é🙂", "x")) != "xéx🙂x": return panic("empty pattern")

    let view = RegexReplacement(RegexAdapter(pattern))
    let view_all = view.replace_all
    if (
        value(view.replace_all("aaa", "b", none)) != "bbb"
        or value(view_all("aa", "b", 2)) != "bb"
    ):
        return panic("Regex interface view")

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
    if (
        result.values() != [1, 2]
        or original.values() != [1, 2]
        or items.values() != [8]
    ):
        return panic("add receiver capture")

    result.remove(
        match some(0):
            some(_):
                items = Set[Int]().add(9)
                1
            none: 2
    )
    if result.values() != [2] or items.values() != [9]: return panic("remove capture")
