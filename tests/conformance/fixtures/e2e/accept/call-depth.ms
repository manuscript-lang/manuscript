# conform: tags=closures,control-flow,interfaces,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/call-depth.ms
from "@std/testing.ms" import expect_contains, expect_equal, expect_fault

type Walker:
    step: Int
    limit: Int

interface Walk:
    def walk(n: Int) -> Int

impl Walk for Walker:
    def walk(n: Int) -> Int:
        if n == self.limit:
            return 0

        return 1 + self.walk(n: n + self.step)

def runaway(n: Int) -> Int:
    return 1 + runaway(n + 1)

def bounded(n: Int, limit: Int) -> Int:
    if n == limit:
        return 0

    return 1 + bounded(n: n + 1, limit: limit)

test "runaway recursion is a fault":
    let message = try expect_fault(
        lambda:
            let ignored = runaway(0)
    )
    message | try expect_contains("call depth limit exceeded")

test "runaway method recursion faults like function recursion":
    let walker = Walker(step: 1, limit: -1)
    let message = try expect_fault(
        lambda:
            let ignored = walker.walk(n: 0)
    )
    message | try expect_contains("call depth limit exceeded")

test "recursion below the limit runs normally":
    (bounded(n: 0, limit: 100000) - 100000) | try expect_equal(0)

test "method recursion below the limit runs normally":
    (Walker(step: 1, limit: 100000).walk(n: 0) - 100000) | try expect_equal(0)
