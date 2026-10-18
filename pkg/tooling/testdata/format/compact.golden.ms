import expect_equal from "@std/testing.ms"

fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int: transform(value)

type Choice:
    case Zero
    case One
    case Other(value: Int)

fn choose(value: Choice) -> String:
    match value:
        Zero:
            return "zero # unchanged"
        # Keep this comment with the arm.
        One:
            return "one"
        Other(number):
            return "value {number}"

fn count() -> Int:
    return apply(
        value: 2,
        transform: fn(value: Int) -> Int: return (value + 10 + 20 + 30 + 40)
    )

test "compact formatting preserves behavior":
    let values = [1, 2, 2, 4, 3, 6]  # Keep this list compact.
    let nested = [[1, 2], [3, 4]]
    let invalid = ["", "[1,", "\{\"a\" 1\}", "tru", "[1] x", "\"abc"]
    let mapped = [1, 2, 3, 4, 5, 6].map(
        transform: fn(value: Int) -> Int:
            return value + 1
    )
    values | try expect_equal(expected: [1, 2, 2, 4, 3, 6])
    nested | try expect_equal(expected: [[1, 2], [3, 4]])
    invalid.length() | try expect_equal(expected: 6)
    mapped | try expect_equal(expected: [2, 3, 4, 5, 6, 7])
    count() | try expect_equal(expected: 102)
    choose(Choice.Zero) | try expect_equal(expected: "zero # unchanged")
    choose(Choice.Other(3)) | try expect_equal(expected: "value 3")
