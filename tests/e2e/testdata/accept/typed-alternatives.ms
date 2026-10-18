import range from "@std/collections.ms"
import panic from "@std/faults.ms"

fn checked(n: Int) Result[Int, String]:
    if n < 0:
        return error("negative")

    return ok(n + 1)

fn chain(n: Int) Result[Int, String]:
    let v = try checked(n)
    return ok(v * 2)

fn deeper(n: Int) Result[Int, String]:
    let a = try chain(n)
    let b = try chain(a)
    return ok(a + b)

fn expression_try(n: Int) Result[Int, String]:
    let x = (try checked(n)) + 100
    return ok(x)

fn passthrough(n: Int) Result[Int, String]:
    return checked(n)

fn through_local(n: Int) Result[Int, String]:
    let r = checked(n)
    return r

fn halve(n: Int) Optional[Int]:
    if n % 2 != 0:
        return none

    return some(n / 2)

fn word(n: Int) Result[String, String]:
    if n == 0:
        return error("zero")

    return ok("w{n}")

fn ratio(n: Int) Result[Float, String]:
    return ok(1.5)

fn nothing(flag: Bool) Result[Unit, String]:
    if flag:
        return ok(unit)

    return error("no")

fn nested(n: Int) Optional[Optional[Int]]:
    if n == 0:
        return none

    return some(halve(n))

fn matched_value(n: Int) Int:
    return checked(n).unwrap_or(-1)

fn closure_return(n: Int) Result[Int, String]:
    if let y = halve(n):
        return ok(y)

    return error("odd")

fn sum_all(count: Int) Result[Int, String]:
    var total = 0

    for i in range(0, count):
        let v = try checked(i)
        total += v

    return ok(total)

test "result matching":
    let v = chain(3).unwrap()
    if not (v == 8):
        return panic("chain ok")

    let failure = chain(-1)
    if not failure.is_error():
        return panic("chain should fail")
    if not (failure.unwrap_error() == "negative"):
        return panic("cause")

test "try chains":
    let v = deeper(1).unwrap()
    if not (v == 4 + 10):
        return panic("deeper {v}")

    let deeper_failure = deeper(-5)
    if not deeper_failure.is_error():
        return panic("deeper should fail")
    if not (deeper_failure.unwrap_error() == "negative"):
        return panic("deeper cause")

    let x = expression_try(4).unwrap()
    if not (x == 105):
        return panic("expression try")
    if not expression_try(-4).is_error():
        return panic("expression try should fail")

    let total = sum_all(5).unwrap()
    if not (total == 15):
        return panic("sum {total}")

test "boxed consumers":
    if not ("{checked(2)}" == "{passthrough(2)}"):
        return panic("display parity")
    if not (checked(2) == through_local(2)):
        return panic("equality")
    if not (checked(-2) == passthrough(-2)):
        return panic("error equality")

    let f = checked
    let v = f(6).unwrap()
    if not (v == 7):
        return panic("first class")
    if not (matched_value(3) == 4):
        return panic("match value")
    if not (matched_value(-3) == -1):
        return panic("match value error")

test "optional and payload kinds":
    if let h = halve(8):
        if not (h == 4):
            return panic("halve")
    else:
        return panic("halve none")

    if halve(7).is_some():
        return panic("halve odd")

    let w = word(3).unwrap()
    if not (w == "w3"):
        return panic("word")

    let r = ratio(1).unwrap()
    if not (r == 1.5):
        return panic("ratio")

    nothing(true).unwrap()

    if let inner = nested(4):
        if not (inner == some(2)):
            return panic("nested inner")
    else:
        return panic("nested none")

    let odd = closure_return(5)
    if not odd.is_error():
        return panic("closure return should fail")
    if not (odd.unwrap_error() == "odd"):
        return panic("closure return cause")

    let even = closure_return(6).unwrap()
    if not (even == 3):
        return panic("closure return ok")

test "list at unwrap":
    let items = [10, 20, 30]
    if not (items.at(0).unwrap() == 10):
        return panic("first")
    if not (items.at(-1).unwrap() == 30):
        return panic("negative index")
    if not (items.at(1).unwrap() + items.at(2).unwrap() == 50):
        return panic("sum")
