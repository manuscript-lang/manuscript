# conform: tags=alternatives,control-flow,interfaces,lists,match,modules,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/direct-method-semantics.ms
import TextError from "@std/core.ms"
import expect_true, fail from "@std/test.ms"

interface Shape:
    fn area() Int
    fn scaled(by: Int) Int
    fn checked(limit: Int) Int!TextError
    fn grow(depth: Int) Int

type Rect:
    w: Int
    h: Int

type Sign:
    case Plus(n: Int)
    case Minus(n: Int)

impl Shape for Rect:
    fn area() Int:
        return self.w * self.h

    fn scaled(by: Int) Int:
        return self.area() * by

    fn checked(limit: Int) Int!TextError:
        if self.area() > limit:
            return error(cause: TextError("too big"))

        return ok(value: self.area())

    fn grow(depth: Int) Int:
        if depth == 0:
            return self.w

        return self.grow(depth: depth - 1) + 1

impl Shape for Sign:
    fn area() Int:
        match self:
            Plus(n): return n
            Minus(n): return 0 - n

    fn scaled(by: Int) Int:
        return self.area() * by

    fn checked(limit: Int) Int!TextError:
        return ok(value: self.area())

    fn grow(depth: Int) Int:
        return depth

fn through(shape: Shape) Int:
    return shape.scaled(by: 2)

fn tried(rect: Rect, limit: Int) Int!TextError:
    let first = try rect.checked(limit: limit)
    return ok(value: first + (try rect.checked(limit: limit + 100)))

fn order(rect: Rect, var log: List[String]) Int:
    log.append(value: "receiver")
    return rect.scaled(by: id(log: var log))

fn id(var log: List[String]) Int:
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
        ok(value): (value == 24) | try expect_true
        error(cause): return fail(cause.message())

    match tried(rect: rect, limit: 11):
        ok(_value): return fail("expected failure")
        error(cause): (cause.message() == "too big") | try expect_true

    var log = List[String]()
    (order(rect: rect, log: var log) == 12) | try expect_true
    (log.join(separator: ",") == "receiver,argument") | try expect_true
