import range from "@std/collections.ms"
import panic from "@std/faults.ms"

fn checked(n: Int) Result[Int, String]:
    if n < 0:
        return error(cause: "negative")

    return ok(value: n + 1)

fn chain(n: Int) Result[Int, String]:
    let v = try checked(n)
    return ok(value: v * 2)

fn deeper(n: Int) Result[Int, String]:
    let a = try chain(n)
    let b = try chain(a)
    return ok(value: a + b)

fn expression_try(n: Int) Result[Int, String]:
    let x = (try checked(n)) + 100
    return ok(value: x)

fn passthrough(n: Int) Result[Int, String]:
    return checked(n)

fn through_local(n: Int) Result[Int, String]:
    let r = checked(n)
    return r

fn halve(n: Int) Optional[Int]:
    if n % 2 != 0:
        return none

    return some(value: n / 2)

fn word(n: Int) Result[String, String]:
    if n == 0:
        return error(cause: "zero")

    return ok(value: "w{n}")

fn ratio(n: Int) Result[Float, String]:
    return ok(value: 1.5)

fn nothing(flag: Bool) Result[Unit, String]:
    if flag:
        return ok(value: unit)

    return error(cause: "no")

fn nested(n: Int) Optional[Optional[Int]]:
    if n == 0:
        return none

    return some(value: halve(n))

fn matched_value(n: Int) Int:
    return checked(n).unwrap_or(-1)

fn closure_return(n: Int) Result[Int, String]:
    if let y = halve(n):
        return ok(value: y)

    return error(cause: "odd")

fn sum_all(count: Int) Result[Int, String]:
    var total = 0

    for i in range(0, count):
        let v = try checked(i)
        total += v

    return ok(value: total)

test "result matching":
    let v = chain(3).unwrap()
    if not (v == 8):
        return panic(message: "chain ok")

    let failure = chain(-1)
    if not failure.is_error():
        return panic(message: "chain should fail")
    if not (failure.unwrap_error() == "negative"):
        return panic(message: "cause")

test "try chains":
    let v = deeper(1).unwrap()
    if not (v == 4 + 10):
        return panic(message: "deeper {v}")

    let deeper_failure = deeper(-5)
    if not deeper_failure.is_error():
        return panic(message: "deeper should fail")
    if not (deeper_failure.unwrap_error() == "negative"):
        return panic(message: "deeper cause")

    let x = expression_try(4).unwrap()
    if not (x == 105):
        return panic(message: "expression try")
    if not expression_try(-4).is_error():
        return panic(message: "expression try should fail")

    let total = sum_all(5).unwrap()
    if not (total == 15):
        return panic(message: "sum {total}")

test "boxed consumers":
    if not ("{checked(2)}" == "{passthrough(2)}"):
        return panic(message: "display parity")
    if not (checked(2) == through_local(2)):
        return panic(message: "equality")
    if not (checked(-2) == passthrough(-2)):
        return panic(message: "error equality")

    let f = checked
    let v = f(n: 6).unwrap()
    if not (v == 7):
        return panic(message: "first class")
    if not (matched_value(3) == 4):
        return panic(message: "match value")
    if not (matched_value(-3) == -1):
        return panic(message: "match value error")

test "optional and payload kinds":
    if let h = halve(8):
        if not (h == 4):
            return panic(message: "halve")
    else:
        return panic(message: "halve none")

    if halve(7).is_some():
        return panic(message: "halve odd")

    let w = word(3).unwrap()
    if not (w == "w3"):
        return panic(message: "word")

    let r = ratio(1).unwrap()
    if not (r == 1.5):
        return panic(message: "ratio")

    nothing(true).unwrap()

    if let inner = nested(4):
        if not (inner == some(value: 2)):
            return panic(message: "nested inner")
    else:
        return panic(message: "nested none")

    let odd = closure_return(5)
    if not odd.is_error():
        return panic(message: "closure return should fail")
    if not (odd.unwrap_error() == "odd"):
        return panic(message: "closure return cause")

    let even = closure_return(6).unwrap()
    if not (even == 3):
        return panic(message: "closure return ok")

test "list at unwrap":
    let items = [10, 20, 30]
    if not (items.at(0).unwrap() == 10):
        return panic(message: "first")
    if not (items.at(-1).unwrap() == 30):
        return panic(message: "negative index")
    if not (items.at(1).unwrap() + items.at(2).unwrap() == 50):
        return panic(message: "sum")
