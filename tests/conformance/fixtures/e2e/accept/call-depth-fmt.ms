// conform: tags=closures,control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/call-depth.ms
import expect_equal from "@std/test/test.ms"

type Walker:
    step: Int
    limit: Int

interface Walk:
    fn walk(n: Int) Int

fn Walker.walk(n: Int) Int:
    if n == self.limit:
        return 0

    return 1 + self.walk(n: n + self.step)

fn bounded(n: Int, limit: Int) Int:
    if n == limit:
        return 0

    return 1 + bounded(n: n + 1, limit: limit)

test "recursion below the limit runs normally":
    (bounded(n: 0, limit: 100000) - 100000) | expect_equal(0)?

test "method recursion below the limit runs normally":
    (Walker(step: 1, limit: 100000).walk(n: 0) - 100000) | expect_equal(0)?
