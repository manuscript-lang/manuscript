import StringError, StringBuilder, from_scalars from "@std/string.ms"

# Conversions between text and values: booleans, integers in any base, and quoted literals.
# Scalar classification lives in `@std/unicode.ms`; whole-string operations such as `fields_by`,
# `trim_chars` and `title` are methods on String.
#
#     import quote, parse_int_radix from "@std/text.ms"
#     quote("a\tb")                  # a double-quoted literal with the escape written out
#     parse_int_radix("-ff", 16)     # -255

# Parses `true`/`false` ignoring case, and `1`/`0`, `t`/`f`, `yes`/`no`, `on`/`off`; anything else is none.
export fn parse_bool(text: String) Bool?:
    let word = text.trim().lower()
    if ["true", "t", "1", "yes", "on"].contains(word):
        return true
    if ["false", "f", "0", "no", "off"].contains(word):
        return false

    return none

# Parses an integer in base 2 to 36 with an optional sign; `_` separators and surrounding
# white space are not accepted. Base 0 chooses the base from a `0x`, `0o` or `0b` prefix and
# otherwise uses 10. An overflow, bad digit or unsupported base is none.
export fn parse_int_radix(text: String, base: Int) Int?:
    var digits = text
    var negative = false

    if let rest = digits.cut_prefix("-"):
        negative = true
        digits = rest.clone()
    else if let rest = digits.cut_prefix("+"):
        digits = rest.clone()

    var radix = base

    if radix == 0:
        radix = 10

        let lowered = digits.lower()

        if lowered.starts_with("0x"):
            radix = 16
            digits = digits.drop(2)
        else if lowered.starts_with("0o"):
            radix = 8
            digits = digits.drop(2)
        else if lowered.starts_with("0b"):
            radix = 2
            digits = digits.drop(2)

    if radix < 2 or radix > 36 or digits.is_empty():
        return none

    var value = 0

    for c in digits.scalar_values():
        var d = 99

        if c >= 48 and c <= 57:
            d = c - 48
        else if c >= 97 and c <= 122:
            d = c - 87
        else if c >= 65 and c <= 90:
            d = c - 55

        if d >= radix:
            return none

        # Accumulate negatively so the most negative Int parses.
        if value < (-9223372036854775807 - 1 + d) / radix:
            return none

        value = value * radix - d

    if negative:
        return value
    if value == -9223372036854775807 - 1:
        return none

    return 0 - value

# Quotes text as a double-quoted literal using the escapes of Manuscript string literals.
# Printable Unicode stays as is; control characters and U+2028/U+2029 become `\u{..}`.
export fn quote(text: String) String:
    return quote_with(text, false)

# Like quote, but every non-ASCII scalar is written as `\u{..}`, so the result is pure ASCII.
export fn quote_ascii(text: String) String:
    return quote_with(text, true)

fn quote_with(text: String, ascii_only: Bool) String:
    var out = StringBuilder()
    out.append("\"")

    for c in text.scalar_values():
        if c == 34:
            out.append("\\\"")
        else if c == 92:
            out.append("\\\\")
        else if c == 10:
            out.append("\\n")
        else if c == 13:
            out.append("\\r")
        else if c == 9:
            out.append("\\t")
        else if (
            c < 32
            or c == 127
            or c == 8232
            or c == 8233
            or (ascii_only and c > 127)
        ):
            out.append("\\u\{" + c.to_string_radix(16) + "\}")
        else:
            out.append(from_scalars([c]).get(""))

    out.append("\"")
    return out.build()

# Reverses quote: reads a double-quoted literal and returns its text. Supports `\"`, `\\`, `\n`,
# `\r`, `\t`, `\0` and `\u{hex}`; anything else, or text that is not fully quoted, is InvalidInput.
export fn unquote(text: String) String!StringError:
    let cs = text.scalar_values()
    if cs.length() < 2 or cs[0] != 34 or cs[cs.length() - 1] != 34:
        return error(StringError.InvalidInput)

    var out = List[Int]()
    var i = 1
    let end = cs.length() - 1

    while i < end:
        let c = cs[i]
        if c == 34:
            return error(StringError.InvalidInput)

        if c != 92:
            out.append(c)
            i += 1
        else if i + 1 >= end:
            return error(StringError.InvalidInput)
        else:
            let e = cs[i + 1]
            i += 2

            if e == 110:
                out.append(10)
            else if e == 114:
                out.append(13)
            else if e == 116:
                out.append(9)
            else if e == 48:
                out.append(0)
            else if e == 34 or e == 92:
                out.append(e)
            else if e == 117 and i < end and cs[i] == 123:
                var j = i + 1
                var hex = List[Int]()

                while j < end and cs[j] != 125:
                    hex.append(cs[j])
                    j += 1

                if j >= end:
                    return error(StringError.InvalidInput)

                let digits = try from_scalars(hex)
                let value = parse_int_radix(digits, 16)

                if let v = value:
                    out.append(v)
                else:
                    return error(StringError.InvalidInput)

                i = j + 1
            else:
                return error(StringError.InvalidInput)

    return from_scalars(out)
