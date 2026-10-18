import {NormalizationForm, StringError} from "@std/string.ms"
import panic from "@std/faults.ms"

fn normalize(form: NormalizationForm, text: String) Result[String, StringError]:
    return form.normalize(text)

fn call[T](operation: fn(text: String, max_bytes: Optional[Int]) T, text: String) T:
    return operation(text, none)

test "typed Unicode forms retain normalization and bound dispatch":
    let decomposed = "é"
    if normalize(NormalizationForm.Nfc, decomposed).get() != "é": return panic(
        "canonical composition"
    )
    if NormalizationForm.Nfd.normalize("é").get() != decomposed: return panic(
        "canonical decomposition"
    )
    if NormalizationForm.Nfkc.normalize("ﬁ").get() != "fi": return panic(
        "compatibility composition"
    )
    if NormalizationForm.Nfkd.normalize("ﬁ").get() != "fi": return panic(
        "compatibility decomposition"
    )

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

        if form.normalize("ﬁé").get() != "ﬁé".normalize(spelling).get(): return panic(
            "existing implementation changed"
        )

    let stored = NormalizationForm.Nfc.normalize
    if call(stored, decomposed).get() != "é": return panic("stored generic operation")

test "typed normalization keeps UTF-8 byte budgets and domain errors":
    let form = NormalizationForm.Nfc
    if form.normalize("é", 2).get() != "é": return panic("exact byte budget")
    if form.normalize("", 0).get() != "": return panic("empty zero budget")
    if form.normalize("é", 1).err() != StringError.LimitExceeded: return panic(
        "UTF-8 byte budget"
    )
    if form.normalize("x", 0).err() != StringError.LimitExceeded: return panic(
        "nonempty zero budget"
    )
    if form.normalize("", -1).err() != StringError.InvalidInput: return panic(
        "negative byte budget"
    )
    if "x".normalize("nfc").err() != StringError.InvalidInput: return panic(
        "legacy form validation"
    )
