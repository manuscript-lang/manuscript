import {expect_equal} from "@std/testing.ms"

test "required replacement count retains zero finite oversized and literal semantics":
    try expect_equal("aaaa".replace_n("a", "b", 0), "aaaa")
    try expect_equal("aaaa".replace_n("a", "b", 1), "baaa")
    try expect_equal("aaaa".replace_n("a", "b", 2), "bbaa")
    try expect_equal("aaaa".replace_n("a", "b", 999), "bbbb")
    try expect_equal("aaaa".replace_n("aa", "x", 2), "xx")
    try expect_equal("aaa".replace_n("a", "aa", 2), "aaaaa")
    try expect_equal("abc".replace_n("z", "large", 2), "abc")
    try expect_equal("abc".replace_n("b", "$1", 2), "a$1c")
    try expect_equal("abc".replace_n("b", "", 1), "ac")
    try expect_equal("a".replace_n("a", "世界", 1).byte_length(), 6)

test "empty patterns use Unicode scalar boundaries without normalization":
    try expect_equal("é😀".replace_n("", "|", 0), "é😀")
    try expect_equal("é😀".replace_n("", "|", 2), "|é|😀")
    try expect_equal("é😀".replace_n("", "|", 99), "|é|😀|")
    try expect_equal("".replace_n("", "x", 5), "x")
    try expect_equal("".replace_n("a", "x", 5), "")
    try expect_equal("e\u{301}".replace_n("é", "x", 2), "e\u{301}")
    try expect_equal("éé".replace_n("é", "😀", 1), "😀é")

fn forward[T](value: T) T: value

test "bound typed and generic calls retain the required count and captured receiver":
    var text = "aaaa"
    let replace = text.replace_n
    text = "zzzz"
    try expect_equal(replace("a", "b", 2), "bbaa")
    let typed: fn(old: String, new: String, max_replacements: Int) String = replace.clone()
    try expect_equal(typed("a", "b", 3), "bbba")
    let generic = forward(replace)
    try expect_equal(generic("a", "b", 1), "baaa")
    try expect_equal("aaaa".replace_first("a", "b", 2), "bbaa")
    try expect_equal("aaaa".replace("a", "b", none), "baaa")

interface CappedReplacement:
    fn replace_n(old: String, new: String, max_replacements: Int) String

type TextAdapter:
    text: String
    replace_n: fn(old: String, new: String, max_replacements: Int) String

impl CappedReplacement for TextAdapter:
    fn replace_n(old: String, new: String, max_replacements: Int) String:
        return self.text.replace_n(old, new, max_replacements)

test "explicit and bound views retain method contracts and callable field shadowing":
    let adapter = TextAdapter(
        "aaaa", fn(old: String, new: String, max_replacements: Int) String: "field"
    )
    try expect_equal(adapter.replace_n("a", "b", 2), "field")
    let view = CappedReplacement(adapter)
    try expect_equal(view.replace_n("a", "b", 2), "bbaa")
    let bound = view.replace_n
    try expect_equal(bound("a", "b", 1), "baaa")
