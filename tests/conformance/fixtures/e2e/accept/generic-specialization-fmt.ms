# conform: tags=control-flow,formatter,generics,modules,mutation,parser,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/generic-specialization.ms
from "@std/testing.ms" import expect_equal
from "@std/collections.ms" import range

def ident[T](x: T) -> T:
    return x

def countdown[T](x: T, n: Int) -> Int:
    if n == 0:
        return 0

    return 1 + countdown(x, n - 1)

def twice[T](x: T) -> T:
    return ident(ident(x))

def depth() -> Int:
    return countdown("s", 5)

test "static specializations are reused across calls":
    var acc = 0
    for i in range(0, 100):
        acc += ident(i)
    try expect_equal(acc, 4950)
    try expect_equal(ident("a"), "a")

test "recursive generics with static arguments":
    try expect_equal(depth(), 5)
    try expect_equal(countdown(1, 3), 3)

test "generic calls with type-variable arguments still resolve":
    try expect_equal(twice(4), 4)
    try expect_equal(twice("b"), "b")
