# conform: tags=closures,control-flow,formatter,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/inline-suites.ms
import expect_equal from "@std/test.ms"

fn double(value: Int) Int: value * 2

fn apply(value: Int, transform: fn(Int) Int) Int: transform(value)

fn choose(value: Int) Int:
    if value > 0: return double(value)
    else: return 0

fn alternate(value: Int) Int:
    if value < 0: return -1
    else if value == 0: return 0
    else:
        return 1

test "inline functions and branches":
    try expect_equal(choose(3), 6)
    try expect_equal(choose(-3), 0)
    try expect_equal(alternate(0), 0)
    try expect_equal(alternate(3), 1)

    let increment = fn(value: Int): value + 1
    try expect_equal(increment(2), 3)

    let result = apply(4, fn value: value * 3)
    try expect_equal(result, 12)

    var count = 0
    while count < 3: count += 1
    try expect_equal(count, 3)

test "inline test": return
