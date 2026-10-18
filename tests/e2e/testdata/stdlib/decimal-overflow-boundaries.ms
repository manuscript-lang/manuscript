import {expect_equal, expect_false} from "@std/testing.ms"
import Decimal from "@std/decimal.ms"

test "Decimal magnitude rounding and underflow boundaries remain unchanged":
    let maximum = 9.999999999999999999999999999999999e6144d
    try expect_false(maximum + 0d != maximum or maximum * 1d != maximum)
    try expect_false(-maximum * 1d != -maximum or - maximum - 0d != -maximum)
    try expect_false(1e-6176d / 10d != 0d or - 1e-6176d / 10d != 0d)
    try expect_equal(1d / 3d, 0.3333333333333333333333333333333333d)
