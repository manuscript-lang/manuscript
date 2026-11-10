import (
    parse_rat, rat_of_int from "@std/math/big.ms",
    expect_equal, expect_error from "@std/test/test.ms",
)

// 2^16777216 has 16777217 bits. BigInt rejects it from its lower size
// bound without computing the oversized power.
test "rational powers preserve numerator and denominator size errors":
    for text in ["2", "-2", "1/2", "-1/2", "2/3"]:
        value := try parse_rat(text)

        for exponent in [16777216, -16777216]:
            failure := try expect_error(value.pow(exponent))
            try expect_equal(failure.kind, "EOVERFLOW")

test "rational powers retain exact ordinary results":
    value := try parse_rat("-2/3")
    try expect_equal((try value.pow(3)).format(), "-8/27")
    try expect_equal((try value.pow(-3)).format(), "-27/8")
    try expect_equal((try value.pow(0)).format(), "1")

test "rational powers retain zero and unit controls":
    zero := rat_of_int(0)
    try expect_equal((try zero.pow(0)).format(), "1")
    try expect_equal((try zero.pow(16777216)).format(), "0")
    try expect_equal((try expect_error(zero.pow(-1))).kind, "EINVAL")

    for exponent in [16777216, -16777216, 16777217, -16777217]:
        try expect_equal((try rat_of_int(1).pow(exponent)).format(), "1")

        expected := if exponent % 2 == 0: "1" else: "-1"
        try expect_equal((try rat_of_int(-1).pow(exponent)).format(), expected)
