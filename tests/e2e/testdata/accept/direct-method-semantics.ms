from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_true, fail

interface Shape:
    def area() -> Int
    def scaled(by: Int) -> Int
    def checked(limit: Int) -> Result[Int, TextError]
    def grow(depth: Int) -> Int

type Rect:
    w: Int
    h: Int

type Sign:
    case Plus(n: Int)
    case Minus(n: Int)

impl Shape for Rect:
    def area() -> Int:
        return self.w * self.h

    def scaled(by: Int) -> Int:
        return self.area() * by

    def checked(limit: Int) -> Result[Int, TextError]:
        if self.area() > limit:
            return error(cause: TextError("too big"))

        return ok(value: self.area())

    def grow(depth: Int) -> Int:
        if depth == 0:
            return self.w

        return self.grow(depth: depth - 1) + 1

impl Shape for Sign:
    def area() -> Int:
        match self:
            case Plus(n): return n
            case Minus(n): return 0 - n

    def scaled(by: Int) -> Int:
        return self.area() * by

    def checked(limit: Int) -> Result[Int, TextError]:
        return ok(value: self.area())

    def grow(depth: Int) -> Int:
        return depth

def through(shape: Shape) -> Int:
    return shape.scaled(by: 2)

def tried(rect: Rect, limit: Int) -> Result[Int, TextError]:
    let first = try rect.checked(limit: limit)
    return ok(value: first + (try rect.checked(limit: limit + 100)))

def order(rect: Rect, var log: List[String]) -> Int:
    log.append(value: "receiver")
    return rect.scaled(by: id(log: var log))

def id(var log: List[String]) -> Int:
    log.append(value: "argument")
    return 1

test "direct methods":
    let rect = Rect(w: 3, h: 4)
    (rect.area() == 12) | try expect_true
    (rect.scaled(by: 3) == 36) | try expect_true
    (through(shape: rect) == 24) | try expect_true
    (through(shape: Plus(n: 5)) == 10) | try expect_true
    (Minus(n: 4).area() == 0 - 4) | try expect_true
    (rect.grow(depth: 10) == 13) | try expect_true

    match tried(rect: rect, limit: 12):
        case ok(value): (value == 24) | try expect_true
        case error(cause): return fail(cause.message())

    match tried(rect: rect, limit: 11):
        case ok(_value): return fail("expected failure")
        case error(cause): (cause.message() == "too big") | try expect_true

    var log = List[String]()
    (order(rect: rect, log: var log) == 12) | try expect_true
    (log.join(separator: ",") == "receiver,argument") | try expect_true
