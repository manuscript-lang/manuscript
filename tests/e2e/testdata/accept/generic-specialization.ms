import panic from "@std/faults.ms"

fn ident[T](x: T) T:
    return x

fn countdown[T](x: T, n: Int) Int:
    if n == 0:
        return 0

    return 1 + countdown(x: x, n: n - 1)

fn twice[T](x: T) T:
    return ident(x: ident(x: x))

fn depth() Int:
    return countdown(x: "s", n: 5)

test "static specializations are reused across calls":
    var i = 0
    var acc = 0

    while i < 100:
        acc = acc + ident(x: i)
        i = i + 1

    if not (acc == 4950):
        return panic(message: "ident")
    if not (ident(x: "a") == "a"):
        return panic(message: "string")

test "recursive generics with static arguments":
    if not (depth() == 5):
        return panic(message: "recursion")
    if not (countdown(x: 1, n: 3) == 3):
        return panic(message: "int recursion")

test "generic calls with type-variable arguments still resolve":
    if not (twice(x: 4) == 4):
        return panic(message: "twice int")
    if not (twice(x: "b") == "b"):
        return panic(message: "twice string")
