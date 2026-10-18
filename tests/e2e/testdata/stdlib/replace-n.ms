import {expect_equal} from "@std/testing.ms"

test "required replacement count retains zero finite oversized and literal semantics":
    "aaaa".replace_n("a", "b", 0) | try expect_equal(expected: "aaaa")
    "aaaa".replace_n("a", "b", 1) | try expect_equal(expected: "baaa")
    "aaaa".replace_n("a", "b", 2) | try expect_equal(expected: "bbaa")
    "aaaa".replace_n("a", "b", 999) | try expect_equal(expected: "bbbb")
    "aaaa".replace_n("aa", "x", 2) | try expect_equal(expected: "xx")
    "aaa".replace_n("a", "aa", 2) | try expect_equal(expected: "aaaaa")
    "abc".replace_n("z", "large", 2) | try expect_equal(expected: "abc")
    "abc".replace_n("b", "$1", 2) | try expect_equal(expected: "a$1c")
    "abc".replace_n("b", "", 1) | try expect_equal(expected: "ac")
    "a".replace_n("a", "世界", 1).byte_length() | try expect_equal(expected: 6)

test "empty patterns use Unicode scalar boundaries without normalization":
    "é😀".replace_n("", "|", 0) | try expect_equal(expected: "é😀")
    "é😀".replace_n("", "|", 2) | try expect_equal(expected: "|é|😀")
    "é😀".replace_n("", "|", 99) | try expect_equal(expected: "|é|😀|")
    "".replace_n("", "x", 5) | try expect_equal(expected: "x")
    "".replace_n("a", "x", 5) | try expect_equal(expected: "")
    "e\u{301}".replace_n("é", "x", 2) | try expect_equal(expected: "e\u{301}")
    "éé".replace_n("é", "😀", 1) | try expect_equal(expected: "😀é")

fn forward[T](value: T) -> T: value

test "bound typed and generic calls retain the required count and captured receiver":
    var text = "aaaa"
    let replace = text.replace_n
    text = "zzzz"
    replace(old: "a", new: "b", max_replacements: 2) | try expect_equal(
        expected: "bbaa"
    )
    let typed: fn(old: String, new: String, max_replacements: Int) -> String = replace
    typed("a", "b", 3) | try expect_equal(expected: "bbba")
    let generic = forward(replace)
    generic("a", "b", 1) | try expect_equal(expected: "baaa")
    "aaaa".replace_first("a", "b", 2) | try expect_equal(expected: "bbaa")
    "aaaa".replace("a", "b", none) | try expect_equal(expected: "baaa")

interface CappedReplacement:
    fn replace_n(old: String, new: String, max_replacements: Int) -> String

type TextAdapter:
    text: String
    replace_n: fn(old: String, new: String, max_replacements: Int) -> String

impl CappedReplacement for TextAdapter:
    fn replace_n(old: String, new: String, max_replacements: Int) -> String:
        return self.text.replace_n(old, new, max_replacements)

test "explicit and bound views retain method contracts and callable field shadowing":
    let adapter = TextAdapter(
        "aaaa",
        fn(old: String, new: String, max_replacements: Int) -> String: "field"
    )
    adapter.replace_n("a", "b", 2) | try expect_equal(expected: "field")
    let view = CappedReplacement(adapter)
    view.replace_n("a", "b", 2) | try expect_equal(expected: "bbaa")
    let bound = view.replace_n
    bound("a", "b", 1) | try expect_equal(expected: "baaa")
