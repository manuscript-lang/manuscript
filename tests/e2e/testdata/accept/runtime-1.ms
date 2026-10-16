import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"

fn amount() -> Result[Decimal, String]:
    return ok(12.50d)

test "explicit standard imports":
    if not ([1, 2].length() == 2):
        return panic(message: "check failed")

    match amount():
        ok(value):
            if not (value == 12.50d):
                return panic(message: "check failed")
        error(_):
            return panic(message: "Unexpected case")
