import Decimal from "@std/decimal.ms"
import expect_equal from "@std/test.ms"

test "decimal comparison aligns every significant digit without losing signs":
    let base: Decimal = 1e33d
    var step: Decimal = 1e33d

    for digits in 0..34:
        let larger = base + step
        try expect_equal(larger.compare(base), 1)
        try expect_equal(base.compare(larger), -1)
        try expect_equal((-larger).compare(-base), -1)
        try expect_equal((-base).compare(-larger), 1)
        step = step / 10d

    try expect_equal(9.999999999999999999999999999999999e6144d.compare(1e6144d), 1)
    try expect_equal((-9.999999999999999999999999999999999e6144d).compare(-1e6144d), -1)
    try expect_equal(1e-6176d.compare(2e-6176d), -1)
    try expect_equal((-1e-6176d).compare(-2e-6176d), 1)
