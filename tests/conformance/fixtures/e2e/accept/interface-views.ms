# conform: tags=alternatives,control-flow,faults,interfaces,lists,optional,records,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/interface-views.ms
import expect_equal from "@std/test/test.ms"

type Cause:
    code: Int
    text: String

impl Error for Cause:
    fn message() String: "cause {self.code}: {self.text}"

type Holder:
    err: Error
    cause: Cause

fn first_error(cause: Cause) Error:
    return cause

fn first_failure(cause: Cause) Int!:
    return error(cause)

fn fresh(cause: Cause, make: Bool) Error:
    if make: return Cause(9, "fresh and also heap allocated text")

    return cause

fn failing(cause: Cause) Int!Cause:
    return error(cause)

fn widened(cause: Cause) Int!:
    return failing(cause)

fn tried(cause: Cause) Int!:
    let v = try failing(cause)
    return ok(v + 1)

fn relay(e: Error) Error:
    return e

fn held(cause: Cause) String:
    let e: Error = cause
    return e.message()

fn through(cause: Cause) Error:
    let e = first_error(cause)
    return e

fn cond(cause: Cause, other: Cause, c: Bool) Error:
    let e = first_error(cause)
    if c: return e

    return other

fn looped(cause: Cause) Error:
    for i in 0..3:
        let e: Error = cause
        if i == 2: return e

    return Cause(7, "fell through the loop with heap text")

fn maybe(cause: Cause, b: Bool) Error?:
    if b: return cause

    return none

fn either(r: Holder, b: Bool) Error:
    if b: return r.err

    return r.cause

fn owned_copy(cause: Cause) List[Error]:
    let e: Error = cause.clone()
    return [e]

fn through_result(cause: Cause) Int!:
    let r: Int! = error(cause)
    return r

fn id[T](x: T) T:
    return x

fn lend_then_relay(cause: Cause) Error:
    let e = first_error(cause)
    return relay(e)

fn lend_id(cause: Cause) Error:
    return id(first_error(cause))

fn rebound(cause: Cause) Error:
    let e: Error = cause
    let e2 = e
    return e2

fn rebound_result(cause: Cause) Int!:
    let r: Int! = error(cause)
    let r2 = r
    return r2

fn rebound_alias_relay(cause: Cause) Error:
    let e: Error = cause
    let e2 = e
    return relay(e2)

test "interface values converted from borrowed values are views":
    var c = Cause(1, "a heap allocated text that is long")
    let other = Cause(2, "another heap allocated text that is long")
    let h = Holder(
        Cause(3, "held heap text that is long enough"),
        Cause(4, "held cause heap text long")
    )
    let kept = owned_copy(c)
    let one = first_error(c)
    let owned: Error = c.clone()
    let message = one.message()
    (
        first_failure(c).err().message() | try expect_equal(
            "cause 1: a heap allocated text that is long"
        )
    )
    (
        widened(c).err().message() | try expect_equal(
            "cause 1: a heap allocated text that is long"
        )
    )
    (
        tried(c).err().message() | try expect_equal(
            "cause 1: a heap allocated text that is long"
        )
    )
    relay(c).message() | try expect_equal("cause 1: a heap allocated text that is long")
    held(c) | try expect_equal("cause 1: a heap allocated text that is long")
    through(c).message() | try expect_equal(
        "cause 1: a heap allocated text that is long"
    )
    c.code = 5
    cond(c, other, true).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    cond(c, other, false).message() | try expect_equal(
        "cause 2: another heap allocated text that is long"
    )
    looped(c).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    fresh(c, false).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    fresh(c, true).message() | try expect_equal(
        "cause 9: fresh and also heap allocated text"
    )
    maybe(c, true).get().message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    maybe(c, false).is_some() | try expect_equal(false)
    either(h, true).message() | try expect_equal(
        "cause 3: held heap text that is long enough"
    )
    either(h, false).message() | try expect_equal("cause 4: held cause heap text long")
    kept[0].message() | try expect_equal("cause 1: a heap allocated text that is long")
    owned.message() | try expect_equal("cause 1: a heap allocated text that is long")
    message | try expect_equal("cause 1: a heap allocated text that is long")
    (
        through_result(c).err().message() | try expect_equal(
            "cause 5: a heap allocated text that is long"
        )
    )
    lend_then_relay(c).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    lend_id(c).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    rebound(c).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
    (
        rebound_result(c).err().message() | try expect_equal(
            "cause 5: a heap allocated text that is long"
        )
    )
    rebound_alias_relay(c).message() | try expect_equal(
        "cause 5: a heap allocated text that is long"
    )
