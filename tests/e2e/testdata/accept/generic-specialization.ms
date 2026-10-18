import range from "@std/collections.ms"
import panic from "@std/faults.ms"

fn ident[T](x: T) T:
    return x

fn countdown[T](x: T, n: Int) Int:
    if n == 0:
        return 0

    return 1 + countdown(x, n - 1)

fn twice[T](x: T) T:
    return ident(ident(x))

fn depth() Int:
    return countdown("s", 5)

test "static specializations are reused across calls":
    var acc = 0
    for i in range(0, 100):
        acc += ident(i)
    if not (acc == 4950):
        return panic("ident")
    if not (ident("a") == "a"):
        return panic("string")

test "recursive generics with static arguments":
    if not (depth() == 5):
        return panic("recursion")
    if not (countdown(1, 3) == 3):
        return panic("int recursion")

test "generic calls with type-variable arguments still resolve":
    if not (twice(4) == 4):
        return panic("twice int")
    if not (twice("b") == "b"):
        return panic("twice string")
