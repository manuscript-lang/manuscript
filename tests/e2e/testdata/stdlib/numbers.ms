import {parse_int, parse_float, NumberError} from "@std/numbers.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "numbers radix and signed boundaries":
    if value(parse_int(text: "7fffffffffffffff", radix: 16)) != 9223372036854775807: return panic(
        "maximum int"
    )
    if (
        value(
            parse_int(text: "-9223372036854775808", radix: 10)
        ) != -9223372036854775808
    ): return panic("minimum int")
    if 255.to_string_radix(radix: 16) != "ff": return panic("radix formatting")
    if value(parse_float("-1.25e2")) != -125.0: return panic("exponent")
    if value(1.25.to_fixed(digits: 2)) != "1.25": return panic("fixed formatting")
    if 1.9.truncate_to_int() != some(1): return panic("float truncation")

test "numbers reject whitespace separators overflow and invalid radix":
    let invalid: Result[Int, NumberError] = error(NumberError.InvalidData)
    for text in [" 1", "1_0", "0x10", "+", "١"]:
        if parse_int(text: text, radix: 10) != invalid: return panic("nondecimal input")
    let overflow: Result[Int, NumberError] = error(NumberError.OutOfRange)
    if parse_int(text: "9223372036854775808", radix: 10) != overflow: return panic(
        "overflow"
    )

    let radix_error: Result[Int, NumberError] = error(NumberError.InvalidInput)
    if parse_int(text: "1", radix: 1) != radix_error: return panic("invalid radix")

    let float_error: Result[Float, NumberError] = error(NumberError.InvalidData)
    for text in [" 1.0", "1_0", "1.", "0x1p2"]:
        if parse_float(text) != float_error: return panic("noncanonical float")
