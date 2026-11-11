// conform: tags=control-flow,faults,interpolation,modules,mutation,numbers,optional,stdlib-collections,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/typed-alternatives.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"

fn checked(n: Int) Int!Error:
    if n < 0:
        return error(Error("negative"))

    return ok(n + 1)

fn chain(n: Int) Int!Error:
    v := checked(n)?
    return ok(v * 2)

fn deeper(n: Int) Int!Error:
    a := chain(n)?
    b := chain(a)?
    return ok(a + b)

fn expression_try(n: Int) Int!Error:
    x := (checked(n)?) + 100
    return ok(x)

fn passthrough(n: Int) Int!Error:
    return checked(n)

fn through_local(n: Int) Int!Error:
    r := checked(n)
    return r

fn halve(n: Int) Int?:
    if n % 2 != 0:
        return none

    return (n / 2)

fn word(n: Int) String!Error:
    if n == 0:
        return error(Error("zero"))

    return ok("w{n}")

fn ratio(n: Int) Float!Error:
    return ok(1.5)

fn nothing(flag: Bool) Unit!Error:
    if flag:
        return ok(unit)

    return error(Error("no"))

fn nested(n: Int) Int??:
    if n == 0:
        return none

    return halve(n)

fn matched_value(n: Int) Int:
    return checked(n).get(-1)

fn closure_return(n: Int) Int!Error:
    if y := halve(n):
        return ok(y)

    return error(Error("odd"))

fn sum_all(count: Int) Int!Error:
    var total = 0

    for i in 0..count:
        v := checked(i)?
        total += v

    return ok(total)

test "result matching":
    v := chain(3).get()
    expect_equal(v, 8)?

    failure := chain(-1)
    expect_false(not failure.is_error())?
    expect_equal(failure.err().message, "negative")?

test "chains?":
    v := deeper(1).get()
    if not (v == 4 + 10): return fail("deeper {v}")

    deeper_failure := deeper(-5)
    expect_false(not deeper_failure.is_error())?
    expect_equal(deeper_failure.err().message, "negative")?

    x := expression_try(4).get()
    expect_equal(x, 105)?
    expect_false(not expression_try(-4).is_error())?

    total := sum_all(5).get()
    if not (total == 15): return fail("sum {total}")

test "boxed consumers":
    expect_equal("{checked(2)}", "{passthrough(2)}")?
    expect_equal(checked(2), through_local(2))?
    expect_equal(checked(-2), passthrough(-2))?

    f := checked
    v := f(6).get()
    expect_equal(v, 7)?
    expect_equal(matched_value(3), 4)?
    expect_equal(matched_value(-3), -1)?

test "optional and payload kinds":
    if h := halve(8):
        expect_equal(h, 4)?
    else:
        return fail("halve none")

    expect_false(halve(7).is_some())?

    w := word(3).get()
    expect_equal(w, "w3")?

    r := ratio(1).get()
    expect_equal(r, 1.5)?
    nothing(true).get()

    if inner := nested(4):
        expect_equal(inner, 2)?
    else:
        return fail("nested none")

    odd := closure_return(5)
    expect_false(not odd.is_error())?
    expect_equal(odd.err().message, "odd")?

    even := closure_return(6).get()
    expect_equal(even, 3)?

test "list at unwrap":
    items := [10, 20, 30]
    expect_equal(items.get(0), 10)?
    expect_equal(items.get(-1), 30)?
    expect_equal(items.get(1) + items.get(2), 50)?
