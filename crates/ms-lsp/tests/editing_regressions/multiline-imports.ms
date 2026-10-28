import NormalizationForm from "@std/string.ms"
import {sqrt} from "@std/math.ms"

fn root(value: Float, form: NormalizationForm) Float:
    if form == NormalizationForm.Nfc: return sqrt(value)

    return value
