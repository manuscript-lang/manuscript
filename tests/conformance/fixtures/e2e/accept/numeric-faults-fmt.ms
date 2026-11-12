// conform: tags=closures,formatter,modules,mutation,numbers,parser,stdlib-string,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/numeric-faults.ms
import expect_contains, expect_equal, expect_fault, expect_true from "@std/test/test.ms"
import StringBuilder from "@std/string_builder.ms"

fn add(a: Int, b: Int) Int: return a + b

fn subtract(a: Int, b: Int) Int: return a - b

fn multiply(a: Int, b: Int) Int: return a * b

fn divide(a: Int, b: Int) Int: return a / b

fn remainder(a: Int, b: Int) Int: return a % b

fn negate(a: Int) Int: return -a

fn flip(a: Float) Float: return -a

test "add high overflows":
    message := expect_fault(
        fn:
            _bad := add(a: 9223372036854775807, b: 1)
    )?
    message | expect_contains("Int overflow;")?

test "add low overflows":
    message := expect_fault(
        fn:
            _bad := add(a: -9223372036854775808, b: -1)
    )?
    message | expect_contains("Int overflow;")?

test "subtract high overflows":
    message := expect_fault(
        fn:
            _bad := subtract(a: 9223372036854775807, b: -1)
    )?
    message | expect_contains("Int overflow;")?

test "subtract low overflows":
    message := expect_fault(
        fn:
            _bad := subtract(a: -9223372036854775808, b: 1)
    )?
    message | expect_contains("Int overflow;")?

test "multiply high overflows":
    message := expect_fault(
        fn:
            _bad := multiply(a: 9223372036854775807, b: 2)
    )?
    message | expect_contains("Int overflow;")?

test "multiply minimum overflows":
    message := expect_fault(
        fn:
            _bad := multiply(a: -9223372036854775808, b: -1)
    )?
    message | expect_contains("Int overflow;")?

test "divide minimum overflows":
    message := expect_fault(
        fn:
            _bad := divide(a: -9223372036854775808, b: -1)
    )?
    message | expect_contains("division overflow;")?

test "divide by zero faults":
    message := expect_fault(
        fn:
            _bad := divide(a: 1, b: 0)
    )?
    message | expect_contains("division by zero;")?

test "remainder by zero faults":
    message := expect_fault(
        fn:
            _bad := remainder(a: 1, b: 0)
    )?
    message | expect_contains("remainder by zero;")?

test "negation":
    (negate(a: 5) == -5) | expect_true?
    (negate(a: -7) == 7) | expect_true?
    (negate(a: 0) == 0) | expect_true?
    (negate(a: 9223372036854775807) == -9223372036854775807) | expect_true?
    (-9223372036854775808 == negate(a: 9223372036854775807) - 1) | expect_true?
    (flip(a: 1.5) == -1.5) | expect_true?
    (1.0 / flip(a: 0.0) < 0.0) | expect_true?
    (1.0 / -0.0 < 0.0) | expect_true?

    var count = -3
    count = count + 1
    (count == -2) | expect_true?

test "negating the minimum overflows":
    message := expect_fault(
        fn:
            _bad := negate(a: -9223372036854775808)
    )?
    message | expect_contains("Int overflow;")?
