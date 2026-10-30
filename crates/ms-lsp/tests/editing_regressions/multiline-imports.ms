import NormalizationForm from "@std/string.ms"
import (
    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    shift_left,
    shift_right,
    count_ones,
    leading_zeros,
    sqrt
) from "@std/math.ms"

fn root(value: Float, form: NormalizationForm) Float:
    if form == NormalizationForm.Nfc: return sqrt(value)

    return value
