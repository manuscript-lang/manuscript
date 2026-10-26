from "@std/test.ms" import expect_contains, expect_equal, expect_fault, expect_true
from "@std/string.ms" import StringBuilder

def add(a: Int, b: Int) -> Int: return a + b

def subtract(a: Int, b: Int) -> Int: return a - b

def multiply(a: Int, b: Int) -> Int: return a * b

def divide(a: Int, b: Int) -> Int: return a / b

def remainder(a: Int, b: Int) -> Int: return a % b

def negate(a: Int) -> Int: return -a

def flip(a: Float) -> Float: return -a

test "add high overflows":
    let message = try expect_fault(
        lambda:
            let bad = add(a: 9223372036854775807, b: 1)
    )
    message | try expect_contains("Int overflow;")

test "add low overflows":
    let message = try expect_fault(
        lambda:
            let bad = add(a: -9223372036854775808, b: -1)
    )
    message | try expect_contains("Int overflow;")

test "subtract high overflows":
    let message = try expect_fault(
        lambda:
            let bad = subtract(a: 9223372036854775807, b: -1)
    )
    message | try expect_contains("Int overflow;")

test "subtract low overflows":
    let message = try expect_fault(
        lambda:
            let bad = subtract(a: -9223372036854775808, b: 1)
    )
    message | try expect_contains("Int overflow;")

test "multiply high overflows":
    let message = try expect_fault(
        lambda:
            let bad = multiply(a: 9223372036854775807, b: 2)
    )
    message | try expect_contains("Int overflow;")

test "multiply minimum overflows":
    let message = try expect_fault(
        lambda:
            let bad = multiply(a: -9223372036854775808, b: -1)
    )
    message | try expect_contains("Int overflow;")

test "divide minimum overflows":
    let message = try expect_fault(
        lambda:
            let bad = divide(a: -9223372036854775808, b: -1)
    )
    message | try expect_contains("Int./: overflow;")

test "divide by zero faults":
    let message = try expect_fault(
        lambda:
            let bad = divide(a: 1, b: 0)
    )
    message | try expect_contains("division by zero;")

test "remainder by zero faults":
    let message = try expect_fault(
        lambda:
            let bad = remainder(a: 1, b: 0)
    )
    message | try expect_contains("remainder by zero;")

test "negation":
    (negate(a: 5) == -5) | try expect_true
    (negate(a: -7) == 7) | try expect_true
    (negate(a: 0) == 0) | try expect_true
    (negate(a: 9223372036854775807) == -9223372036854775807) | try expect_true
    (-9223372036854775808 == negate(a: 9223372036854775807) - 1) | try expect_true
    (flip(a: 1.5) == -1.5) | try expect_true
    (1.0 / flip(a: 0.0) < 0.0) | try expect_true
    (1.0 / -0.0 < 0.0) | try expect_true

    var count = -3
    count = count + 1
    (count == -2) | try expect_true

test "negating the minimum overflows":
    let message = try expect_fault(
        lambda:
            let bad = negate(a: -9223372036854775808)
    )
    message | try expect_contains("Int overflow;")
