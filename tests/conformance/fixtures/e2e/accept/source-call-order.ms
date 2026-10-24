# conform: tags=faults,generics,match,modules,mutation,optional,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/source-call-order.ms
from "@std/testing.ms" import expect_equal

def pair(a: Int, b: Int) -> Int: a * 10 + b

test "arguments":
    var value = 1
    let option: Optional[Int] = some(2)
    let result = pair(
        a: value,
        b: match option:
            case some(i):
                value = 9
                i
            case none: 0
    )
    try expect_equal(result, 12)

def optional(value: Optional[Int]) -> Int: value.get()

def defaulted(value: Int = 3) -> Int: value

def identity[T](value: T) -> T: value

test "source call dispatch contracts":
    try expect_equal(optional(4), 4)
    try expect_equal(defaulted(5), 5)
    try expect_equal(defaulted(), 3)
    try expect_equal(pair(b: 2, a: 1), 12)

    let callback = pair
    try expect_equal(callback(a: 3, b: 4), 34)
    try expect_equal(identity(6), 6)
