import panic from "@std/faults.ms"

import parse from "@std/bigint.ms"
import multiply from "@std/bigint.ms"
import format from "@std/bigint.ms"
import BigInt from "@std/bigint.ms"
import Result from "@std/result.ms"
import LibraryError from "@std/errors.ms"

fn verify_bigint() -> Result[Unit, LibraryError]:
    let large = try parse(text: "18446744073709551616", radix: 10, max_digits: 30)
    if not (format(value: multiply(left: large, right: large), radix: 10) == "340282366920938463463374607431768211456"):
        return panic(message: "check failed")
    return ok(value: unit)

test "large integers are exact":
    let expected: Result[Unit, LibraryError] = ok(value: unit)
    if not (verify_bigint() == expected):
        return panic(message: "check failed")
