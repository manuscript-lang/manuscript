import expect_equal from "@std/test/test.ms"
import NormalizationForm from "@std/string.ms"

type BudgetCase:
    form: String
    text: String
    expected: String

test "normalization preserves all four forms and literal replacement characters":
    try expect_equal("e\u{301}".normalize("NFC").get(), "é")
    try expect_equal("é".normalize("NFD").get(), "e\u{301}")
    try expect_equal("ﬁ①".normalize("NFKC").get(), "fi1")
    try expect_equal("ﬁ①".normalize("NFKD").get(), "fi1")
    try expect_equal("a\u{315}\u{300}".normalize("NFC").get(), "à\u{315}")
    try expect_equal("a\u{315}\u{300}".normalize("NFD").get(), "a\u{300}\u{315}")
    try expect_equal("각".normalize("NFD").get(), "각")
    try expect_equal(NormalizationForm.Nfc.normalize("e\u{301}").get(), "é")
    try expect_equal(NormalizationForm.Nfd.normalize("é").get(), "e\u{301}")
    try expect_equal(NormalizationForm.Nfkc.normalize("ﬁ①").get(), "fi1")
    try expect_equal(NormalizationForm.Nfkd.normalize("ﬁ①").get(), "fi1")

    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        try expect_equal("a\u{fffd}\u{0}".normalize(form).get(), "a\u{fffd}\u{0}")
        try expect_equal("".normalize(form, 0).get(), "")

test "normalization keeps exact exceeded zero negative and invalid form budgets":
    for normalization in [
        BudgetCase("NFC", "e\u{301}", "é"), BudgetCase("NFD", "é", "e\u{301}"),
        BudgetCase("NFKC", "ﬁ①", "fi1"), BudgetCase("NFKD", "ﬁ①", "fi1")
    ]:
        let size = normalization.expected.byte_length()
        try expect_equal(
            normalization.text.normalize(normalization.form, size).get(),
            normalization.expected.clone()
        )
        try expect_equal(
            normalization.text.normalize(
                normalization.form, size - 1
            ).err(),
            Error(
                "string: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        try expect_equal(
            normalization.text.normalize(normalization.form, 0).err(),
            Error(
                "string: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        try expect_equal(
            normalization.text.normalize(normalization.form, -1).err(),
            Error("string: invalid input", kind: ErrorCategory.InvalidInput)
        )

    for form in ["", "nfc", "NFC\u{0}", "UNKNOWN"]:
        try expect_equal(
            "é".normalize(form).err(),
            Error("string: invalid input", kind: ErrorCategory.InvalidInput)
        )
        try expect_equal(
            "é".normalize(form, -1).err(),
            Error("string: invalid input", kind: ErrorCategory.InvalidInput)
        )

test "normalization retains lookahead across a complete combining segment":
    let text = "a" + "\u{315}\u{300}".repeat(32).get()
    let decomposed = "a" + "\u{300}".repeat(32).get() + "\u{315}".repeat(32).get()
    let composed = "à" + "\u{300}".repeat(31).get() + "\u{315}".repeat(32).get()
    try expect_equal(text.normalize("NFC").get(), composed.clone())
    try expect_equal(text.normalize("NFD").get(), decomposed.clone())
    try expect_equal(text.normalize("NFKC").get(), composed)
    try expect_equal(text.normalize("NFKD").get(), decomposed)
    try expect_equal(
        text.normalize("NFC", 0).err(),
        Error("string: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
