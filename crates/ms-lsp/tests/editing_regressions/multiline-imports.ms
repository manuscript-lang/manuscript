from "@std/string.ms" import NormalizationForm
from "@std/math.ms" import (
    sqrt,
)

def root(value: Float, form: NormalizationForm) -> Float:
    if form == NormalizationForm.Nfc: return sqrt(value)
    return value
