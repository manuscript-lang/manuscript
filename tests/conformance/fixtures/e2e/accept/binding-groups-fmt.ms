# conform: tags=closures,destructuring,formatter,interpolation,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/binding-groups.ms
from "@std/testing.ms" import expect_equal, expect_false

let (
    LOW = 1
    HIGH: Int = LOW + 9
)
export let (
    LABEL = f"range {LOW}..{HIGH}"
)

test "a constant group declares each constant":
    try expect_false(not (HIGH == 10 and LABEL == "range 1..10"))

test "a var group declares mutable locals":
    var (
        total = 0
        step = lambda (value: Int) -> Int:
            return value + 1
    )
    total = step(total)
    try expect_equal(total, 1)

test "a let group declares immutable locals":
    let (
        name = "Ada"
        [first, second] = [1, 2]
    )
    try expect_false(not (name == "Ada" and first + second == 3))
