import (
	NormalizationForm from "@std/string.ms",
	expect_equal from "@std/test/test.ms",
)

type BudgetCase:
	form: String
	text: String
	expected: String

test "normalization preserves all four forms and literal replacement characters":
	expect_equal("e\u{301}".normalize("NFC").get(), "é")?
	expect_equal("é".normalize("NFD").get(), "e\u{301}")?
	expect_equal("ﬁ①".normalize("NFKC").get(), "fi1")?
	expect_equal("ﬁ①".normalize("NFKD").get(), "fi1")?
	expect_equal("a\u{315}\u{300}".normalize("NFC").get(), "à\u{315}")?
	expect_equal("a\u{315}\u{300}".normalize("NFD").get(), "a\u{300}\u{315}")?
	expect_equal("각".normalize("NFD").get(), "각")?
	expect_equal(NormalizationForm.Nfc.normalize("e\u{301}").get(), "é")?
	expect_equal(NormalizationForm.Nfd.normalize("é").get(), "e\u{301}")?
	expect_equal(NormalizationForm.Nfkc.normalize("ﬁ①").get(), "fi1")?
	expect_equal(NormalizationForm.Nfkd.normalize("ﬁ①").get(), "fi1")?

	for form in ["NFC", "NFD", "NFKC", "NFKD"]:
		expect_equal("a\u{fffd}\u{0}".normalize(form).get(), "a\u{fffd}\u{0}")?
		expect_equal("".normalize(form, 0).get(), "")?

test "normalization keeps exact exceeded zero negative and invalid form budgets":
	for normalization in [
		BudgetCase("NFC", "e\u{301}", "é"), BudgetCase("NFD", "é", "e\u{301}"),
		BudgetCase("NFKC", "ﬁ①", "fi1"), BudgetCase("NFKD", "ﬁ①", "fi1")
	]:
		size := normalization.expected.byte_length()
		expect_equal(
			normalization.text.normalize(normalization.form, size).get(),
			normalization.expected.clone()
		)?
		expect_equal(
			normalization.text.normalize(
				normalization.form, size - 1
			).err(),
			Error("string: limit exceeded", kind: "EOVERFLOW")
		)?
		expect_equal(
			normalization.text.normalize(normalization.form, 0).err(),
			Error("string: limit exceeded", kind: "EOVERFLOW")
		)?
		expect_equal(
			normalization.text.normalize(normalization.form, -1).err(),
			Error("string: invalid input", kind: "EINVAL")
		)?

	for form in ["", "nfc", "NFC\u{0}", "UNKNOWN"]:
		expect_equal(
			"é".normalize(form).err(), Error("string: invalid input", kind: "EINVAL")
		)?
		expect_equal(
			"é".normalize(form, -1).err(),
			Error("string: invalid input", kind: "EINVAL")
		)?

test "normalization retains lookahead across a complete combining segment":
	text := "a" + "\u{315}\u{300}".repeat(32).get()
	decomposed := "a" + "\u{300}".repeat(32).get() + "\u{315}".repeat(32).get()
	composed := "à" + "\u{300}".repeat(31).get() + "\u{315}".repeat(32).get()
	expect_equal(text.normalize("NFC").get(), composed.clone())?
	expect_equal(text.normalize("NFD").get(), decomposed.clone())?
	expect_equal(text.normalize("NFKC").get(), composed)?
	expect_equal(text.normalize("NFKD").get(), decomposed)?
	expect_equal(
		text.normalize("NFC", 0).err(),
		Error("string: limit exceeded", kind: "EOVERFLOW")
	)?
