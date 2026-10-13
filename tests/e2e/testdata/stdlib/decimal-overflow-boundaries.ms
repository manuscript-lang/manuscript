import Decimal from "@std/decimal.ms"
import panic from "@std/faults.ms"

test "Decimal magnitude rounding and underflow boundaries remain unchanged":
    let maximum = 9.999999999999999999999999999999999e6144d
    if maximum + 0d != maximum or maximum * 1d != maximum: return panic(
        "maximum magnitude"
    )
    if - maximum * 1d != -maximum or - maximum - 0d != -maximum: return panic(
        "negative maximum"
    )
    if 1e-6176d / 10d != 0d or - 1e-6176d / 10d != 0d: return panic("underflow to zero")
    if 1d / 3d != 0.3333333333333333333333333333333333d: return panic(
        "34-digit rounding"
    )
