// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

test "title and capitalize use the titlecase mapping":
	expect_equal("ǆungla".title(), "ǅungla")?
	expect_equal("ß".title(), "Ss")?
	expect_equal("ﬁne".capitalize(), "Fine")?
	expect_equal("ŉx".capitalize(), "ʼNx")?
	expect_equal("hello wORLD it's 3rd".title(), "Hello World It's 3rd")?
	expect_equal("".title(), "")?

test "title keeps a final sigma final":
	expect_equal("ΑΣ".title(), "Ας")?
	expect_equal("ΟΔΥΣΣΕΥΣ ΑΣ".title(), "Οδυσσευς Ας")?

test "equal_fold treats sharp s and its capital as equal":
	expect_true("ß".equal_fold("ẞ"))?
	expect_true("Straße".equal_fold("STRASSE"))?
	expect_false("a".equal_fold("b"))?
