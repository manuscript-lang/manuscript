from "@std/testing.ms" import expect_equal, expect_contains, expect_fault

test "padding returns a plain String":
    try expect_equal("7".pad_start(3, "0"), "007")
    try expect_equal("id".pad_end(5, "."), "id...")
    try expect_equal("x".pad_start(4, "ab"), "abax")
    try expect_equal("x".pad_end(4, "ab"), "xaba")

test "padding counts scalars":
    try expect_equal("é".pad_start(3, "🙂"), "🙂🙂é")
    try expect_equal("x".pad_end(4, "é🙂"), "xé🙂é")

test "a short target, negative target or empty padding leaves the text unchanged":
    try expect_equal("abc".pad_start(2, "-"), "abc")
    try expect_equal("abc".pad_end(3, "-"), "abc")
    try expect_equal("x".pad_start(-1, " "), "x")
    try expect_equal("x".pad_end(4, ""), "x")
    try expect_equal("".pad_start(2, ""), "")

test "a table row needs no unwrap":
    let row = "total".pad_end(8, " ") + 42.to_string().pad_start(5, " ")
    try expect_equal(row, "total      42")

test "padding beyond the string limit faults":
    let message = try expect_fault(
        lambda:
            let huge = "ab".pad_start(9223372036854775807, "xyz")
    )
    message | try expect_contains("limit exceeded")

test "fixed-digit float formatting returns a plain String":
    try expect_equal(3.14159.to_fixed(2), "3.14")
    try expect_equal(2.5.to_fixed(0), "2")
    try expect_equal(1234.5.to_precision(3), "1.23e+3")
    try expect_equal(0.00015.to_exponential(1), "1.5e-4")
    try expect_equal(1.005.to_fixed(2), "1.00")

test "a digit count outside the range faults":
    let fixed = try expect_fault(
        lambda:
            let text = 1.0.to_fixed(101)
    )
    fixed | try expect_contains("to_fixed")

    let negative = try expect_fault(
        lambda:
            let text = 1.0.to_fixed(-1)
    )
    negative | try expect_contains("to_fixed")

    let precision = try expect_fault(
        lambda:
            let text = 1.0.to_precision(0)
    )
    precision | try expect_contains("to_precision")

    let exponential = try expect_fault(
        lambda:
            let text = 1.0.to_exponential(101)
    )
    exponential | try expect_contains("to_exponential")
