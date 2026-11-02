import compile, from_scalars from "@std/string.ms"
import (
    msstd_unicode_is_alphabetic,
    msstd_unicode_is_alphanumeric,
    msstd_unicode_is_numeric,
    msstd_unicode_is_lowercase,
    msstd_unicode_is_uppercase,
    msstd_unicode_is_whitespace,
    msstd_unicode_is_control,
    msstd_unicode_is_ascii
) from "@std/internal/unicode.ms"

# Tests Unicode scalar values (integers), using the Unicode data of the pinned Rust toolchain.
# Every predicate returns false for negative values, surrogates and values above U+10FFFF.
# Example: `is_alphabetic("é".scalar_at(0))` is true; no case mapping or normalization is applied.

# Tests the Unicode Alphabetic property, including alphabetic combining marks, not only letter categories.
export fn is_alphabetic(scalar: Int) Bool:
    return msstd_unicode_is_alphabetic(scalar)

# Tests Alphabetic or the Unicode numeric categories Nd, Nl and No.
export fn is_alphanumeric(scalar: Int) Bool:
    return msstd_unicode_is_alphanumeric(scalar)

# Tests numeric categories Nd, Nl and No, including fractions; this is broader than decimal digits.
export fn is_numeric(scalar: Int) Bool:
    return msstd_unicode_is_numeric(scalar)

# Tests the Unicode Lowercase property, including Other_Lowercase characters.
export fn is_lowercase(scalar: Int) Bool:
    return msstd_unicode_is_lowercase(scalar)

# Tests the Unicode Uppercase property, including Other_Uppercase characters.
export fn is_uppercase(scalar: Int) Bool:
    return msstd_unicode_is_uppercase(scalar)

# Tests the Unicode White_Space property; excludes the byte-order mark and zero-width space.
export fn is_whitespace(scalar: Int) Bool:
    return msstd_unicode_is_whitespace(scalar)

# Tests Unicode control characters (general category Cc), excluding format characters such as a zero-width joiner.
export fn is_control(scalar: Int) Bool:
    return msstd_unicode_is_control(scalar)

# Tests whether the scalar is in the ASCII range U+0000 through U+007F, including controls.
export fn is_ascii(scalar: Int) Bool:
    return msstd_unicode_is_ascii(scalar)

# Reports whether the scalar is a decimal digit `0` to `9`.
export fn is_digit(scalar: Int) Bool:
    return scalar >= 48 and scalar <= 57

# Reports whether the scalar is punctuation (general category P).
export fn is_punctuation(scalar: Int) Bool:
    return in_category(scalar, "P")

# Reports whether the scalar is a symbol (general category S).
export fn is_symbol(scalar: Int) Bool:
    return in_category(scalar, "S")

# Reports whether the scalar is a combining mark (general category M).
export fn is_mark(scalar: Int) Bool:
    return in_category(scalar, "M")

fn in_category(scalar: Int, category: String) Bool:
    if scalar < 0 or scalar > 1114111:
        return false
    if is_ascii(scalar) and (is_digit(scalar) or is_alphanumeric(scalar)):
        return false

    let text = from_scalars([scalar])
    if let s = text:
        if let re = compile("^\\p\{" + category + "\}$"):
            return re.matches(s)
    return false
