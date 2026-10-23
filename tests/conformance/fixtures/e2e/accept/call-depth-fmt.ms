# conform: tags=closures,control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/call-depth.ms
import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

type Walker:
    step: Int
    limit: Int

interface Walk:
    fn walk(n: Int) Int

impl Walk for Walker:
    fn walk(n: Int) Int:
        if n == self.limit:
            return 0

        return 1 + self.walk(n: n + self.step)

fn runaway(n: Int) Int:
    return 1 + runaway(n + 1)

fn bounded(n: Int, limit: Int) Int:
    if n == limit:
        return 0

    return 1 + bounded(n: n + 1, limit: limit)

test "runaway recursion is a fault":
    let message = try expect_fault(
        fn():
            let ignored = runaway(0)
    )
    message | try expect_contains("call depth limit exceeded")

test "runaway method recursion faults like function recursion":
    let walker = Walker(step: 1, limit: -1)
    let message = try expect_fault(
        fn():
            let ignored = walker.walk(n: 0)
    )
    message | try expect_contains("call depth limit exceeded")

test "recursion below the limit runs normally":
    (bounded(n: 0, limit: 100000) - 100000) | try expect_equal(0)

test "method recursion below the limit runs normally":
    (Walker(step: 1, limit: 100000).walk(n: 0) - 100000) | try expect_equal(0)
