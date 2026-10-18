import panic from "@std/faults.ms"

test "required replacement count retains zero finite oversized and literal semantics":
    if "aaaa".replace_n("a", "b", 0) != "aaaa": return panic("zero count")
    if "aaaa".replace_n("a", "b", 1) != "baaa": return panic("one count")
    if "aaaa".replace_n("a", "b", 2) != "bbaa": return panic("finite count")
    if "aaaa".replace_n("a", "b", 999) != "bbbb": return panic("oversized count")
    if "aaaa".replace_n("aa", "x", 2) != "xx": return panic("nonoverlapping matches")
    if "aaa".replace_n("a", "aa", 2) != "aaaaa": return panic("inserted text rescanned")
    if "abc".replace_n("z", "large", 2) != "abc": return panic("no match")
    if "abc".replace_n("b", "$1", 2) != "a$1c": return panic(
        "replacement text was expanded"
    )
    if "abc".replace_n("b", "", 1) != "ac": return panic("deletion")
    if "a".replace_n("a", "世界", 1).byte_length() != 6:
        return panic("count became a byte budget")

test "empty patterns use Unicode scalar boundaries without normalization":
    if "é😀".replace_n("", "|", 0) != "é😀": return panic("empty zero")
    if "é😀".replace_n("", "|", 2) != "|é|😀": return panic("scalar boundaries")
    if "é😀".replace_n("", "|", 99) != "|é|😀|": return panic("end boundary")
    if "".replace_n("", "x", 5) != "x": return panic("empty receiver boundary")
    if "".replace_n("a", "x", 5) != "": return panic("empty receiver no match")
    if "e\u{301}".replace_n("é", "x", 2) != "e\u{301}": return panic("normalization")
    if "éé".replace_n("é", "😀", 1) != "😀é": return panic("Unicode literal")

fn forward[T](value: T) T: value

test "bound typed and generic calls retain the required count and captured receiver":
    var text = "aaaa"
    let replace = text.replace_n
    text = "zzzz"
    if replace(old: "a", new: "b", max_replacements: 2) != "bbaa":
        return panic("stored receiver")

    let typed: fn(old: String, new: String, max_replacements: Int) String = replace
    if typed("a", "b", 3) != "bbba": return panic("typed count")

    let generic = forward(replace)
    if generic("a", "b", 1) != "baaa": return panic("generic count")
    if "aaaa".replace_first("a", "b", 2) != "bbaa": return panic(
        "compatibility first cap"
    )
    if "aaaa".replace("a", "b", none) != "baaa": return panic("compatibility default")

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
        "aaaa",
        fn(old: String, new: String, max_replacements: Int) String: "field"
    )
    if adapter.replace_n("a", "b", 2) != "field": return panic("field shadowing")

    let view = CappedReplacement(adapter)
    if view.replace_n("a", "b", 2) != "bbaa": return panic("explicit method view")

    let bound = view.replace_n
    if bound("a", "b", 1) != "baaa": return panic("bound view")
