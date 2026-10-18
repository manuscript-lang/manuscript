import panic from "@std/faults.ms"
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
    if code(P(1, "a")) != code(P(1, "a")): return panic("record")
    if code(P(1, "a")) == code(P(2, "a")): return panic("record differs")
    if code(Line(1, some(2))) != code(Line(1, some(2))): return panic("alt")
    if code(Dot(1)) == code(Line(1, none)): return panic("alt differs")
    if code("abc") != "abc".hash() or 7.hash() != code(7): return panic("scalar")
    if code(some(3)) != code(some(3)) or code(12.50d) != code(12.5d): return panic(
        "opt/decimal"
    )
    if code(true) == code(false): return panic("bool")
