import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"

type State:
    calls: Int
    closed: Int

type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failed"

impl Closeable for State:
    fn close() Unit:
        self.closed = self.closed + 1

fn operation(state: State, fail: Bool) Result[Unit, Failure]:
    state.calls = state.calls + 1
    if fail: return error(Failure(42))

    return ok(unit)

fn exact(state: State, fail: Bool) Result[String, Failure]:
    with resource = state:
        try operation(state: state, fail: fail)
        state.calls = state.calls + 10

    return ok("done")

fn widened(state: State) Result[Int, Error]:
    try operation(state: state, fail: true)
    return ok(0)

test "standalone try evaluates once and continues on Unit success":
    let state = State(calls: 0, closed: 0)

    match exact(state: state, fail: false):
        ok(value):
            if value != "done": return panic("success lost")
        error(cause): return panic("unexpected failure")

    if state.calls != 11 or state.closed != 1: return panic("success order changed")

test "standalone try propagates and cleans up before returning":
    let state = State(calls: 0, closed: 0)

    match exact(state: state, fail: true):
        ok(value): return panic("failure swallowed")
        error(cause):
            if cause.code != 42: return panic("payload lost")

    if state.calls != 1 or state.closed != 1: return panic("failure order changed")

test "standalone try preserves concrete errors at Error boundaries":
    let state = State(calls: 0, closed: 0)

    let cause = match widened(state):
        ok(value): return panic("failure swallowed")
        error(cause): cause

    match cause:
        Failure(value):
            if value.code != 42: return panic("payload lost")
        _: return panic("concrete error lost")

    if state.calls != 1: return panic("operation repeated")

test "standalone try in closure returns from that closure":
    let state = State(calls: 0, closed: 0)
    let callback = fn() Result[Unit, Failure]:
        if true: try operation(state: state, fail: true)
        return ok(unit)

    match callback():
        ok(value): return panic("failure swallowed")
        error(cause):
            if cause.code != 42: return panic("payload lost")

    if state.calls != 1: return panic("operation repeated")
