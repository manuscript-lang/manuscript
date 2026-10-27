from "@std/test.ms" import expect_equal

test "replace changes every nonoverlapping match and replace_first changes one":
    try expect_equal("aaaa".replace("a", "b"), "bbbb")
    try expect_equal("aaaa".replace_first("a", "b"), "baaa")
    try expect_equal("aaa".replace("aa", "b"), "ba")
    try expect_equal("aaa".replace("a", "aa"), "aaaaaa")
    try expect_equal("abc".replace("z", "large"), "abc")
    try expect_equal("abc".replace_first("z", "large"), "abc")
    try expect_equal("abc".replace("b", "$1"), "a$1c")
    try expect_equal("abcabc".replace("b", ""), "acac")
    try expect_equal("a-b-c".replace(old: "-", new: "+"), "a+b+c")
    try expect_equal("a-b-c".replace_first(old: "-", new: "+"), "a+b-c")
    try expect_equal("a".replace("a", "世界").byte_length(), 6)

test "empty patterns use Unicode scalar boundaries without normalization":
    try expect_equal("ab".replace("", "-"), "-a-b-")
    try expect_equal("é😀".replace("", "|"), "|é|😀|")
    try expect_equal("é😀".replace_first("", "|"), "|é😀")
    try expect_equal("".replace("", "x"), "x")
    try expect_equal("".replace("a", "x"), "")
    try expect_equal(f"e\u{301}".replace("é", "x"), f"e\u{301}")
    try expect_equal("éé".replace("é", "😀"), "😀😀")
    try expect_equal("éé".replace_first("é", "😀"), "😀é")

def forward[T](value: T) -> T: value

test "bound typed and generic calls keep the all-versus-first split":
    let text = "aaaa"
    let replace = text.replace
    try expect_equal(replace("a", "b"), "bbbb")

    let typed: Callable[[String, String], String] = text.replace_first
    try expect_equal(typed("a", "b"), "baaa")

    let generic = forward(text.replace)
    try expect_equal(generic("aa", "x"), "xx")

interface Replacement:
    def replace(old: String, new: String) -> String

type TextAdapter:
    text: String
    replace: Callable[[String, String], String]

impl Replacement for TextAdapter:
    def replace(old: String, new: String) -> String:
        return self.text.replace(old, new)

test "explicit and bound views retain method contracts and callable field shadowing":
    let adapter = TextAdapter(
        "aaaa", lambda (old: String, new: String) -> String: "field"
    )
    try expect_equal(adapter.replace("a", "b"), "field")

    let view: Replacement = adapter
    try expect_equal(view.replace("a", "b"), "bbbb")

    let bound = view.replace
    try expect_equal(bound("aa", "b"), "bb")

test "replacing long text with a shorter or equal string trims, shares or inlines the result":
    let long = "word word word word word word word word word word"
    try expect_equal(long.replace("word", "w"), "w w w w w w w w w w")
    try expect_equal(
        long.replace("word", "WORD"),
        "WORD WORD WORD WORD WORD WORD WORD WORD WORD WORD"
    )
    try expect_equal(long.replace("word ", ""), "word")
    try expect_equal(long.replace("word", "").byte_length(), 9)
    try expect_equal(long.replace("missing", "x"), long)
    try expect_equal(long.replace("word word", "ww"), "ww ww ww ww ww")

    let wide = "é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é"
    try expect_equal(wide.replace("é", "e"), "e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e")
    try expect_equal(wide.replace("-", "").byte_length(), 40)

test "join sizes its result exactly across the inline and heap boundary":
    let empty: List[String] = []
    try expect_equal(empty.join(","), "")
    try expect_equal(["a"].join(","), "a")
    try expect_equal(["", ""].join(""), "")
    try expect_equal(["", ""].join(","), ",")
    try expect_equal(["ab", "cd", "ef"].join(""), "abcdef")
    try expect_equal(["abcdefg", "hijklmn"].join(", ").byte_length(), 16)
    try expect_equal(["abcdefg", "hijklmn"].join(", "), "abcdefg, hijklmn")
    try expect_equal(["abcdefgh", "ijklmno"].join(", ").byte_length(), 17)
    try expect_equal(["abcdefgh", "ijklmno"].join(", "), "abcdefgh, ijklmno")
    try expect_equal(["é", "世界", "😀"].join("·"), "é·世界·😀")
    try expect_equal(
        ["one", "two", "three", "four", "five", "six", "seven"].join("--"),
        "one--two--three--four--five--six--seven"
    )
