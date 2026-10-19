# conform: tags=alternatives,control-flow,decimal,formatter,generics,modules,optional,parser,records,stdlib-decimal,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/derived-hash.ms
import {expect_equal, expect_false, expect_not_equal} from "@std/testing.ms"
import Decimal from "@std/decimal.ms"

type P:
    x: Int
    name: String

type Shape:
    case Dot(x: Int)
    case Line(a: Int, b: Optional[Int])

fn code[T: Hashable](value: T) Int:
    return value.hash()

test "derived hashes agree for equal values and are stable":
    try expect_equal(code(P(1, "a")), code(P(1, "a")))
    try expect_not_equal(code(P(1, "a")), code(P(2, "a")))
    try expect_equal(code(Line(1, some(2))), code(Line(1, some(2))))
    try expect_not_equal(code(Dot(1)), code(Line(1, none)))
    try expect_false(code("abc") != "abc".hash() or 7.hash() != code(7))
    try expect_false(code(some(3)) != code(some(3)) or code(12.50d) != code(12.5d))
    try expect_not_equal(code(true), code(false))
