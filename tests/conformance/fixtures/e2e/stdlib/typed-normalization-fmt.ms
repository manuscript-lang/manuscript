# conform: tags=closures,control-flow,faults,formatter,generics,match,modules,optional,parser,stdlib-string,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/typed-normalization.ms
from "@std/testing.ms" import expect_equal
from "@std/string.ms" import NormalizationForm, StringError

def normalize(form: NormalizationForm, text: String) -> Result[String, StringError]:
    return form.normalize(text)

def call[T](operation: Callable[[String, Optional[Int]], T], text: String) -> T:
    return operation(text, none)

test "typed Unicode forms retain normalization and bound dispatch":
    let decomposed = "é"
    try expect_equal(normalize(NormalizationForm.Nfc, decomposed).get(), "é")
    try expect_equal(NormalizationForm.Nfd.normalize("é").get(), decomposed)
    try expect_equal(NormalizationForm.Nfkc.normalize("ﬁ").get(), "fi")
    try expect_equal(NormalizationForm.Nfkd.normalize("ﬁ").get(), "fi")

    for form in [
        NormalizationForm.Nfc, NormalizationForm.Nfd, NormalizationForm.Nfkc,
        NormalizationForm.Nfkd
    ]:
        let spelling = match form:
            case Nfc: "NFC"
            case Nfd: "NFD"
            case Nfkc: "NFKC"
            case Nfkd: "NFKD"

        try expect_equal(form.normalize("ﬁé").get(), "ﬁé".normalize(spelling).get())

    let stored = NormalizationForm.Nfc.normalize
    try expect_equal(call(stored, decomposed).get(), "é")

test "typed normalization keeps UTF-8 byte budgets and domain errors":
    let form = NormalizationForm.Nfc
    try expect_equal(form.normalize("é", 2).get(), "é")
    try expect_equal(form.normalize("", 0).get(), "")
    try expect_equal(form.normalize("é", 1).err(), StringError.LimitExceeded)
    try expect_equal(form.normalize("x", 0).err(), StringError.LimitExceeded)
    try expect_equal(form.normalize("", -1).err(), StringError.InvalidInput)
    try expect_equal("x".normalize("nfc").err(), StringError.InvalidInput)
