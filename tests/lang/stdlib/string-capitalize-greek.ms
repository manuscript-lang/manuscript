// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// Greek letters with ypogegrammeni have titlecase letters of their own (U+1F88 and
// kin), and some end in the combining U+0345 rather than a capital iota.
test "capitalize gives the Greek titlecase forms" {
	void expect_equal("ᾀ".capitalize(), "ᾈ")?
	void expect_equal("ᾈ".capitalize(), "ᾈ")?
	void expect_equal("ᾼ".capitalize(), "ᾼ")?
	void expect_equal("ῃ".capitalize(), "ῌ")?
	void expect_equal("ῌ".capitalize(), "ῌ")?
	void expect_equal("ῳ".capitalize(), "ῼ")?
	void expect_equal("ῼ".capitalize(), "ῼ")?
	void expect_equal("ᾲ".capitalize(), "Ὰͅ")?
	void expect_equal("ᾴ".capitalize(), "Άͅ")?
	void expect_equal("ᾷ".capitalize(), "ᾼ͂")?
	void expect_equal("ῂ".capitalize(), "Ὴͅ")?
	void expect_equal("ῄ".capitalize(), "Ήͅ")?
	void expect_equal("ῇ".capitalize(), "ῌ͂")?
	void expect_equal("ῲ".capitalize(), "Ὼͅ")?
	void expect_equal("ῴ".capitalize(), "Ώͅ")?
	void expect_equal("ῷ".capitalize(), "ῼ͂")?
	void expect_equal("ǆ".capitalize(), "ǅ")?
	void expect_equal("ß".capitalize(), "Ss")?
	return ok()
}
