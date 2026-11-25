// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

test "title and capitalize use the titlecase mapping" {
	expect_equal("ǆungla".title(), "ǅungla")?
	expect_equal("ß".title(), "Ss")?
	expect_equal("ﬁne".capitalize(), "Fine")?
	expect_equal("ŉx".capitalize(), "ʼNx")?
	expect_equal("hello wORLD it's 3rd".title(), "Hello World It's 3rd")?
	expect_equal("".title(), "")?
	expect_equal("  a--b'c  9x  Z".title(), "  A--B'c  9x  Z")?
	expect_equal("ünï fox lazy DOG".title(), "Ünï Fox Lazy Dog")?
	expect_equal("fox ünï".title(), "Fox Ünï")?
}

test "title keeps a final sigma final" {
	expect_equal("ΑΣ".title(), "Ας")?
	expect_equal("ΟΔΥΣΣΕΥΣ ΑΣ".title(), "Οδυσσευς Ας")?
}

test "equal_fold treats sharp s and its capital as equal" {
	expect_true("ß".equal_fold("ẞ"))?
	expect_true("Straße".equal_fold("STRASSE"))?
	expect_false("a".equal_fold("b"))?
	expect_true("The Quick".equal_fold("tHE qUICK"))?
	expect_true("".equal_fold(""))?
	expect_false("abc".equal_fold("abcd"))?
	expect_false("abcd".equal_fold("abc"))?
	expect_false("abc".equal_fold("ab\u{e9}"))?
	expect_false("ab".equal_fold("ab\u{e9}"))?
	expect_true("ss".equal_fold("ß"))?
	expect_true("k".equal_fold("\u{212a}"))?
	expect_true("abcß".equal_fold("ABCSS"))?
	expect_false("abx".equal_fold("ABCß"))?
}
