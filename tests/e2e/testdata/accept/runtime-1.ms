import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Decimal from "@std/decimal.ms"
import Result from "@std/result.ms"
import map_error from "@std/result.ms"

fn amount() -> Result[Decimal, String]:
    return ok(value: 12.50d)

test "explicit standard imports":
    if not ([1, 2].length() == 2):
        return panic(message: "check failed")
    let outcome = map_error(
        result: amount(),
        transform: fn(cause: String) -> Int:
            return cause.byte_length()
    )
    match outcome:
        ok(value):
            if not (value == 12.50d):
                return panic(message: "check failed")
        error(_):
            return panic(message: "Unexpected case")
