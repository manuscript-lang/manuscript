import Decimal from "@std/decimal.ms"
import expect_equal from "@std/test.ms"

test "decimal comparison orders signs exponent gaps and overlapping digits":
    let ascending = [
        -1e6144d, -1e34d, -9999999999999999999999999999999999d, -1e33d, -1d, -1e-6176d,
        0d, 1e-6176d, 1d, 9999999999999999999999999999999999d, 1e34d, 1e6144d
    ]

    for i in 0..ascending.length():
        try expect_equal(ascending[i].compare(ascending[i]), 0)

        for j in (i + 1)..ascending.length():
            try expect_equal(ascending[i].compare(ascending[j]), -1)
            try expect_equal(ascending[j].compare(ascending[i]), 1)

    try expect_equal(1.1d.compare(1d), 1)
    try expect_equal((-1.1d).compare(-1d), -1)
