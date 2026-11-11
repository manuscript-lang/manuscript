import expect_equal from "@std/test/test.ms"

test "replace changes every nonoverlapping match and replace_first changes one":
	expect_equal("aaaa".replace("a", "b"), "bbbb")?
	expect_equal("aaaa".replace_first("a", "b"), "baaa")?
	expect_equal("aaa".replace("aa", "b"), "ba")?
	expect_equal("aaa".replace("a", "aa"), "aaaaaa")?
	expect_equal("abc".replace("z", "large"), "abc")?
	expect_equal("abc".replace_first("z", "large"), "abc")?
	expect_equal("abc".replace("b", "$1"), "a$1c")?
	expect_equal("abcabc".replace("b", ""), "acac")?
	expect_equal("a-b-c".replace(old: "-", new: "+"), "a+b+c")?
	expect_equal("a-b-c".replace_first(old: "-", new: "+"), "a+b-c")?
	expect_equal("a".replace("a", "世界").byte_length(), 6)?

test "empty patterns use Unicode scalar boundaries without normalization":
	expect_equal("ab".replace("", "-"), "-a-b-")?
	expect_equal("é😀".replace("", "|"), "|é|😀|")?
	expect_equal("é😀".replace_first("", "|"), "|é😀")?
	expect_equal("".replace("", "x"), "x")?
	expect_equal("".replace("a", "x"), "")?
	expect_equal("e\u{301}".replace("é", "x"), "e\u{301}")?
	expect_equal("éé".replace("é", "😀"), "😀😀")?
	expect_equal("éé".replace_first("é", "😀"), "😀é")?

test "replace_first handles early and late matches across output sizes":
	expect_equal("abcabc".replace_first("abc", "X"), "Xabc")?
	expect_equal("abcabc".replace_first("bc", "LONG"), "aLONGabc")?
	expect_equal("abcabc".replace_first("bc", ""), "aabc")?
	expect_equal("abcabc".replace_first("cab", "é🙂"), "abé🙂c")?
	expect_equal("é🙂é".replace_first("🙂", "X"), "éXé")?
	expect_equal("abcdefghijklmno".replace_first("o", "世界"), "abcdefghijklmn世界")?
	expect_equal("abcdefghijklmno".replace_first("missing", "世界"), "abcdefghijklmno")?

fn forward[T](value: T) T: value

test "bound typed and generic calls keep the all-versus-first split":
	text := "aaaa"
	replace := text.replace
	expect_equal(replace("a", "b"), "bbbb")?

	typed: fn(String, String) String := text.replace_first
	expect_equal(typed("a", "b"), "baaa")?

	generic := forward(text.replace)
	expect_equal(generic("aa", "x"), "xx")?

test "replacing long text with a shorter or equal string trims, shares or inlines the result":
	long := "word word word word word word word word word word"
	expect_equal(long.replace("word", "w"), "w w w w w w w w w w")?
	expect_equal(
		long.replace("word", "WORD"),
		"WORD WORD WORD WORD WORD WORD WORD WORD WORD WORD",
	)?
	expect_equal(long.replace("word ", ""), "word")?
	expect_equal(long.replace("word", "").byte_length(), 9)?
	expect_equal(long.replace("missing", "x"), long)?
	expect_equal(long.replace("word word", "ww"), "ww ww ww ww ww")?

	wide := "é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é-é"
	expect_equal(wide.replace("é", "e"), "e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e-e")?
	expect_equal(wide.replace("-", "").byte_length(), 40)?

test "join sizes its result exactly across the inline and heap boundary":
	empty: List[String] := []
	expect_equal(empty.join(","), "")?
	expect_equal(["a"].join(","), "a")?
	expect_equal(["", ""].join(""), "")?
	expect_equal(["", ""].join(","), ",")?
	expect_equal(["ab", "cd", "ef"].join(""), "abcdef")?
	expect_equal(["abcdefg", "hijklmn"].join(", ").byte_length(), 16)?
	expect_equal(["abcdefg", "hijklmn"].join(", "), "abcdefg, hijklmn")?
	expect_equal(["abcdefgh", "ijklmno"].join(", ").byte_length(), 17)?
	expect_equal(["abcdefgh", "ijklmno"].join(", "), "abcdefgh, ijklmno")?
	expect_equal(["é", "世界", "😀"].join("·"), "é·世界·😀")?
	expect_equal(
		["one", "two", "three", "four", "five", "six", "seven"].join("--"),
		"one--two--three--four--five--six--seven",
	)?
