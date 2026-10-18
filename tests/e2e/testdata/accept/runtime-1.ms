import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"

fn amount() Result[Decimal, String]:
    return ok(12.50d)

test "explicit standard imports":
    if not ([1, 2].length() == 2):
        return panic("check failed")
    if not (amount().unwrap_or(0.0d) == 12.50d):
        return panic("check failed")
