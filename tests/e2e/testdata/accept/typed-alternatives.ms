import range from "@std/collections.ms"
import panic from "@std/faults.ms"

fn checked(n: Int) -> Result[Int, String]:
    if n < 0:
        return error(cause: "negative")

    return ok(value: n + 1)

fn chain(n: Int) -> Result[Int, String]:
    let v = try checked(n)
    return ok(value: v * 2)

fn deeper(n: Int) -> Result[Int, String]:
    let a = try chain(n)
    let b = try chain(a)
    return ok(value: a + b)

fn expression_try(n: Int) -> Result[Int, String]:
    let x = (try checked(n)) + 100
    return ok(value: x)

fn passthrough(n: Int) -> Result[Int, String]:
    return checked(n)

fn through_local(n: Int) -> Result[Int, String]:
    let r = checked(n)
    return r

fn halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none

    return some(value: n / 2)

fn word(n: Int) -> Result[String, String]:
    if n == 0:
        return error(cause: "zero")

    return ok(value: "w{n}")

fn ratio(n: Int) -> Result[Float, String]:
    return ok(value: 1.5)

fn nothing(flag: Bool) -> Result[Unit, String]:
    if flag:
        return ok(value: unit)

    return error(cause: "no")

fn nested(n: Int) -> Optional[Optional[Int]]:
    if n == 0:
        return none

    return some(value: halve(n))

fn matched_value(n: Int) -> Int:
    let r = match checked(n):
    ok(v):
        v
    error(_):
        -1

    return r

fn closure_return(n: Int) -> Result[Int, String]:
    let y = match halve(n):
    some(h):
        h
    none:
        return error(cause: "odd")

    return ok(value: y)

fn sum_all(count: Int) -> Result[Int, String]:
    var total = 0

    for i in range(0, count):
        let v = try checked(i)
        total = total + v

    return ok(value: total)

test "result matching":
    match chain(3):
    ok(v):
        if not (v == 8):
            return panic(message: "chain ok")
    error(_):
        return panic(message: "chain error")

    match chain(-1):
    ok(_):
        return panic(message: "chain should fail")
    error(cause):
        if not (cause == "negative"):
            return panic(message: "cause")

test "try chains":
    match deeper(1):
    ok(v):
        if not (v == 4 + 10):
            return panic(message: "deeper {v}")
    error(_):
        return panic(message: "deeper error")

    match deeper(-5):
    ok(_):
        return panic(message: "deeper should fail")
    error(e):
        if not (e == "negative"):
            return panic(message: "deeper cause")

    match expression_try(4):
    ok(v):
        if not (v == 105):
            return panic(message: "expression try")
    error(_):
        return panic(message: "expression try error")

    match expression_try(-4):
    ok(_):
        return panic(message: "expression try should fail")
    error(_):
        unit

    match sum_all(5):
    ok(v):
        if not (v == 15):
            return panic(message: "sum {v}")
    error(_):
        return panic(message: "sum error")

test "boxed consumers":
    if not ("{checked(2)}" == "{passthrough(2)}"):
        return panic(message: "display parity")
    if not (checked(2) == through_local(2)):
        return panic(message: "equality")
    if not (checked(-2) == passthrough(-2)):
        return panic(message: "error equality")

    let f = checked

    match f(n: 6):
    ok(v):
        if not (v == 7):
            return panic(message: "first class")
    error(_):
        return panic(message: "first class error")

    if not (matched_value(3) == 4):
        return panic(message: "match value")
    if not (matched_value(-3) == -1):
        return panic(message: "match value error")

test "optional and payload kinds":
    match halve(8):
    some(h):
        if not (h == 4):
            return panic(message: "halve")
    none:
        return panic(message: "halve none")

    match halve(7):
    some(_):
        return panic(message: "halve odd")
    none:
        unit

    match word(3):
    ok(w):
        if not (w == "w3"):
            return panic(message: "word")
    error(_):
        return panic(message: "word error")

    match ratio(1):
    ok(r):
        if not (r == 1.5):
            return panic(message: "ratio")
    error(_):
        return panic(message: "ratio error")

    match nothing(true):
    ok(u):
        if not (u == unit):
            return panic(message: "unit payload")
    error(_):
        return panic(message: "unit error")

    match nested(4):
    some(inner):
        if not (inner == some(value: 2)):
            return panic(message: "nested inner")
    none:
        return panic(message: "nested none")

    match closure_return(5):
    ok(_):
        return panic(message: "closure return should fail")
    error(e):
        if not (e == "odd"):
            return panic(message: "closure return cause")

    match closure_return(6):
    ok(v):
        if not (v == 3):
            return panic(message: "closure return ok")
    error(_):
        return panic(message: "closure return error")

test "list at unwrap":
    let items = [10, 20, 30]
    if not (items.at(0).unwrap() == 10):
        return panic(message: "first")
    if not (items.at(-1).unwrap() == 30):
        return panic(message: "negative index")
    if not (items.at(1).unwrap() + items.at(2).unwrap() == 50):
        return panic(message: "sum")
