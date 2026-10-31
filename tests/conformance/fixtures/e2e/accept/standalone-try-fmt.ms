# conform: tags=closures,control-flow,formatter,interfaces,match,modules,parser,records,stdlib-cleanup,stdlib-testing,strings,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/standalone-try.ms
import expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test.ms"
import Closeable from "@std/core.ms"
import read_file, temporary, write_file from "@std/fs.ms"

type State:
    calls: Int
    marker: String

type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failed"

# Cleanup runs on a moved copy, so the marker file is the only way to observe it.
impl Closeable for State:
    var fn close() Unit!:
        let _written = write_file(self.marker, "closed", true)
        return ok(unit)

fn operation(var state: State, fail: Bool) Unit!Failure:
    state.calls += 1
    if fail: return error(Failure(42))

    return ok(unit)

fn exact(state: State, fail: Bool) String!Failure:
    let resource = state
    var work = State(resource.calls, resource.marker.clone())
    try operation(var work, fail)
    work.calls += 10
    return ok("done {work.calls}")

fn widened(var state: State) Int!:
    try operation(var state, fail: true)
    return ok(0)

fn closed(marker: String) Bool:
    return read_file(marker).is_ok()

test "standalone try evaluates once and continues on Unit success":
    let temporary = temporary("manuscript-try-") | try expect_ok
    let marker = "{temporary.path()}/marker"
    let value = try exact(State(0, marker.clone()), fail: false)
    try expect_equal(value, "done 11")
    try expect_true(closed(marker))

test "standalone try propagates and cleans up before returning":
    let temporary = temporary("manuscript-try-") | try expect_ok
    let marker = "{temporary.path()}/marker"
    let failed = exact(State(0, marker.clone()), fail: true)
    try expect_false(failed.is_ok())
    try expect_equal(failed.err().code, 42)
    try expect_true(closed(marker))

test "standalone try preserves concrete errors at Error boundaries":
    var state = State(0, "")
    let outcome = widened(var state)
    try expect_false(outcome.is_ok())

    let cause = outcome.err()

    match cause:
        Failure(value):
            try expect_equal(value.code, 42)
        _: return fail("concrete error lost")

    try expect_equal(state.calls, 1)

test "standalone try in closure returns from that closure":
    let callback = fn() Unit!Failure:
        var inner = State(0, "")
        if true: try operation(var inner, fail: true)
        return ok(unit)

    let outcome = callback()
    try expect_false(outcome.is_ok())
    try expect_equal(outcome.err().code, 42)
