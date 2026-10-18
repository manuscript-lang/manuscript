import {expect_equal} from "@std/testing.ms"
import {NormalizationForm, StringError} from "@std/string.ms"

fn normalize(form: NormalizationForm, text: String) -> Result[String, StringError]:
    return form.normalize(text)

fn call[T](
    operation: fn(text: String, max_bytes: Optional[Int]) -> T,
    text: String
) -> T:
    return operation(text, none)

test "typed Unicode forms retain normalization and bound dispatch":
    let decomposed = "é"
    normalize(NormalizationForm.Nfc, decomposed).unwrap() | try expect_equal(
        expected: "é"
    )
    (
        NormalizationForm.Nfd.normalize("é").unwrap() | try expect_equal(
            expected: decomposed
        )
    )
    NormalizationForm.Nfkc.normalize("ﬁ").unwrap() | try expect_equal(expected: "fi")
    NormalizationForm.Nfkd.normalize("ﬁ").unwrap() | try expect_equal(expected: "fi")

    for form in [
        NormalizationForm.Nfc,
        NormalizationForm.Nfd,
        NormalizationForm.Nfkc,
        NormalizationForm.Nfkd
    ]:
        let spelling = match form:
            Nfc: "NFC"
            Nfd: "NFD"
            Nfkc: "NFKC"
            Nfkd: "NFKD"

        (
            form
            .normalize("ﬁé")
            .unwrap() | try expect_equal(
                expected: ("ﬁé".normalize(spelling).unwrap())
            )
        )

    let stored = NormalizationForm.Nfc.normalize
    call(stored, decomposed).unwrap() | try expect_equal(expected: "é")

test "typed normalization keeps UTF-8 byte budgets and domain errors":
    let form = NormalizationForm.Nfc
    form.normalize("é", max_bytes: 2).unwrap() | try expect_equal(expected: "é")
    form.normalize("", max_bytes: 0).unwrap() | try expect_equal(expected: "")
    (
        form.normalize("é", max_bytes: 1).unwrap_error() | try expect_equal(
            expected: StringError.LimitExceeded
        )
    )
    (
        form.normalize("x", max_bytes: 0).unwrap_error() | try expect_equal(
            expected: StringError.LimitExceeded
        )
    )
    (
        form.normalize("", max_bytes: -1).unwrap_error() | try expect_equal(
            expected: StringError.InvalidInput
        )
    )
    "x".normalize("nfc").unwrap_error() | try expect_equal(
        expected: StringError.InvalidInput
    )
