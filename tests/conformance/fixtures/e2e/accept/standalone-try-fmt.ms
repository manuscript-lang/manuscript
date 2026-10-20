# conform: tags=closures,control-flow,formatter,interfaces,match,modules,parser,records,stdlib-cleanup,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/standalone-try.ms
import {expect_equal, expect_false, fail} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"

type State:
    calls: Int
    closed: Int

type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failed"

impl Closeable for State:
    var fn close() Unit:
        self.closed += 1

fn operation(var state: State, fail: Bool) Result[Unit, Failure]:
    state.calls += 1
    if fail: return error(Failure(42))

    return ok(unit)

fn exact(var state: State, fail: Bool) Result[String, Failure]:
    with resource = state:
        try operation(var state, fail)
        state.calls += 10

    return ok("done")

fn widened(var state: State) Result[Int, Error]:
    try operation(var state, fail: true)
    return ok(0)

test "standalone try evaluates once and continues on Unit success":
    var state = State(0, 0)
    let value = try exact(var state, fail: false)
    try expect_equal(value, "done")
    try expect_false(state.calls != 11 or state.closed != 1)

test "standalone try propagates and cleans up before returning":
    var state = State(0, 0)
    let failed = exact(var state, fail: true)
    try expect_false(failed.is_ok())
    try expect_equal(failed.err().code, 42)
    try expect_false(state.calls != 1 or state.closed != 1)

test "standalone try preserves concrete errors at Error boundaries":
    var state = State(0, 0)
    let outcome = widened(var state)
    try expect_false(outcome.is_ok())
    let cause = outcome.err()

    match cause:
        Failure(value):
            try expect_equal(value.code, 42)
        _: return fail("concrete error lost")

    try expect_equal(state.calls, 1)

test "standalone try in closure returns from that closure":
    var state = State(0, 0)
    let callback = fn() Result[Unit, Failure]:
        if true: try operation(var state, fail: true)
        return ok(unit)
    let outcome = callback()
    try expect_false(outcome.is_ok())
    try expect_equal(outcome.err().code, 42)
    try expect_equal(state.calls, 1)
