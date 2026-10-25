# conform: tags=closures,control-flow,formatter,interfaces,match,modules,parser,records,stdlib-cleanup,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/standalone-try.ms
from "@std/testing.ms" import expect_equal, expect_false, expect_ok, expect_true, fail
from "@std/core.ms" import Closeable
from "@std/fs.ms" import filesystem

type State:
    calls: Int
    marker: String

type Failure:
    code: Int

impl Error for Failure:
    def message() -> String: "failed"

# Cleanup runs on a moved copy, so the marker file is the only way to observe it.
impl Closeable for State:
    var def close() -> Unit:
        let written = filesystem().write_file(self.marker, "closed", True)

def operation(var state: State, fail: Bool) -> Result[Unit, Failure]:
    state.calls += 1
    if fail: return error(Failure(42))

    return ok(())

def exact(state: State, fail: Bool) -> Result[String, Failure]:
    with let resource = state:
        var work = resource.clone()
        try operation(var work, fail)
        work.calls += 10
        return ok(f"done {work.calls}")

def widened(var state: State) -> Result[Int, Error]:
    try operation(var state, fail: True)
    return ok(0)

def closed(marker: String) -> Bool:
    return filesystem().read_file(marker).is_ok()

test "standalone try evaluates once and continues on Unit success":
    let fs = filesystem()

    with let temporary = (fs.temporary("manuscript-try-") | try expect_ok):
        let marker = f"{temporary.path()}/marker"
        let value = try exact(State(0, marker), fail: False)
        try expect_equal(value, "done 11")
        try expect_true(closed(marker))

test "standalone try propagates and cleans up before returning":
    let fs = filesystem()

    with let temporary = (fs.temporary("manuscript-try-") | try expect_ok):
        let marker = f"{temporary.path()}/marker"
        let failed = exact(State(0, marker), fail: True)
        try expect_false(failed.is_ok())
        try expect_equal(failed.err().code, 42)
        try expect_true(closed(marker))

test "standalone try preserves concrete errors at Error boundaries":
    var state = State(0, "")
    let outcome = widened(var state)
    try expect_false(outcome.is_ok())

    let cause = outcome.err()

    match cause:
        case Failure(value):
            try expect_equal(value.code, 42)
        case _: return fail("concrete error lost")

    try expect_equal(state.calls, 1)

test "standalone try in closure returns from that closure":
    let callback = lambda () -> Result[Unit, Failure]:
        var inner = State(0, "")
        if True: try operation(var inner, fail: True)
        return ok(())

    let outcome = callback()
    try expect_false(outcome.is_ok())
    try expect_equal(outcome.err().code, 42)
