// conform: tags=alternatives,control-flow,decimal,generics,modules,optional,records,stdlib-decimal,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/derived-hash.ms
import expect_equal, expect_false, expect_not_equal from "@std/test/test.ms"
import Decimal from "@std/math/decimal.ms"

type P:
    x: Int
    name: String

enum Shape:
    Dot(x: Int)
    Line(a: Int, b: Int?)

fn code[T: Hashable](value: T) Int:
    return value.hash()

test "derived hashes agree for equal values and are stable":
    expect_equal(code(P(1, "a")), code(P(1, "a")))?
    expect_not_equal(code(P(1, "a")), code(P(2, "a")))?
    expect_equal(code(Line(1, 2)), code(Line(1, 2)))?
    expect_not_equal(code(Dot(1)), code(Line(1, none)))?
    expect_false(code("abc") != "abc".hash() or 7.hash() != code(7))?
    expect_false(code(3) != code(3) or code(12.50d) != code(12.5d))?
    expect_not_equal(code(true), code(false))?
