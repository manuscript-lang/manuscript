# conform: tags=closures,control-flow,formatter,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/inline-suites.ms
from "@std/testing.ms" import expect_equal

def double(value: Int) -> Int: value * 2

def apply(value: Int, transform: Callable[[Int], Int]) -> Int: transform(value)

def choose(value: Int) -> Int:
    if value > 0: return double(value)
    else: return 0

def alternate(value: Int) -> Int:
    if value < 0: return -1
    elif value == 0: return 0
    else:
        return 1

test "inline functions and branches":
    try expect_equal(choose(3), 6)
    try expect_equal(choose(-3), 0)
    try expect_equal(alternate(0), 0)
    try expect_equal(alternate(3), 1)

    let increment = lambda (value: Int): value + 1
    try expect_equal(increment(2), 3)

    let result = apply(4, lambda value: value * 3)
    try expect_equal(result, 12)

    var count = 0
    while count < 3: count += 1
    try expect_equal(count, 3)

test "inline test": return
