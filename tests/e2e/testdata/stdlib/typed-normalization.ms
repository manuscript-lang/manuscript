import {NormalizationForm, StringError} from "@std/string.ms"
import panic from "@std/faults.ms"

fn normalize(form: NormalizationForm, text: String) -> Result[String, StringError]:
    return form.normalize(text)

fn call[T](
    operation: fn(text: String, max_bytes: Optional[Int]) -> T,
    text: String
) -> T:
    return operation(text, none)

test "typed Unicode forms retain normalization and bound dispatch":
    let decomposed = "é"
    if normalize(NormalizationForm.Nfc, decomposed).unwrap() != "é": return panic(
        "canonical composition"
    )
    if NormalizationForm.Nfd.normalize("é").unwrap() != decomposed: return panic(
        "canonical decomposition"
    )
    if NormalizationForm.Nfkc.normalize("ﬁ").unwrap() != "fi": return panic(
        "compatibility composition"
    )
    if NormalizationForm.Nfkd.normalize("ﬁ").unwrap() != "fi": return panic(
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

        if form.normalize("ﬁé").unwrap() != "ﬁé".normalize(spelling).unwrap(): return panic(
            "existing implementation changed"
        )

    let stored = NormalizationForm.Nfc.normalize
    if call(stored, decomposed).unwrap() != "é": return panic(
        "stored generic operation"
    )

test "typed normalization keeps UTF-8 byte budgets and domain errors":
    let form = NormalizationForm.Nfc
    if form.normalize("é", max_bytes: 2).unwrap() != "é": return panic(
        "exact byte budget"
    )
    if form.normalize("", max_bytes: 0).unwrap() != "": return panic(
        "empty zero budget"
    )
    if form.normalize("é", max_bytes: 1).unwrap_error() != StringError.LimitExceeded: return panic(
        "UTF-8 byte budget"
    )
    if form.normalize("x", max_bytes: 0).unwrap_error() != StringError.LimitExceeded: return panic(
        "nonempty zero budget"
    )
    if form.normalize("", max_bytes: -1).unwrap_error() != StringError.InvalidInput: return panic(
        "negative byte budget"
    )
    if "x".normalize("nfc").unwrap_error() != StringError.InvalidInput: return panic(
        "legacy form validation"
    )
