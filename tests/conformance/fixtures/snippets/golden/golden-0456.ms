// conform: tags=diagnostics
// conform: phase=check
import NormalizationForm from "@std/string.ms"
fn choose(form: NormalizationForm) Unit:
    return unit
fn wrong() Unit:
    choose("NFC")
