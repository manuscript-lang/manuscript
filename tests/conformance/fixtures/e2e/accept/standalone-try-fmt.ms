// conform: tags=closures,control-flow,formatter,interfaces,match,modules,parser,records,stdlib-cleanup,stdlib-testing,strings,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/standalone-try.ms
import expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test/test.ms"
import Closeable from "@std/core.ms"
import read_file, temporary, write_file from "@std/os/fs.ms"

type State:
    calls: Int
    marker: String

type Failure:
    code: Int

// Cleanup runs on a moved copy, so the marker file is the only way to observe it.
fn var State.close() Unit!:
    _written := write_file(self.marker, "closed", true).wait()

fn operation(var state: State, fail: Bool) Unit!Failure:
    state.calls += 1
    if fail: return error(Failure(42))

fn exact(state: State, fail: Bool) String!Failure:
    resource := state
    var work = State(resource.calls, resource.marker.clone())
    operation(var work, fail)?
    work.calls += 10
    return ok("done {work.calls}")

fn widened(var state: State) Int!:
    operation(var state, fail: true).map_error(
        fn cause: Error("failed", details: {"code": cause.code.to_string()})
    )?
    return ok(0)

fn closed(marker: String) Bool:
    return read_file(marker).wait().is_ok()

test "standalone evaluates? once and continues on Unit success":
    temporary := temporary("manuscript-try-") | expect_ok?
    marker := "{temporary.path()}/marker"
    value := exact(State(0, marker.clone()), fail: false).get()
    expect_equal(value, "done 11")?
    expect_true(closed(marker))?

test "standalone propagates? and cleans up before returning":
    temporary := temporary("manuscript-try-") | expect_ok?
    marker := "{temporary.path()}/marker"
    failed := exact(State(0, marker.clone()), fail: true)
    expect_false(failed.is_ok())?
    expect_equal(failed.err().code, 42)?
    expect_true(closed(marker))?

test "standalone converts? errors explicitly at Error boundaries":
    var state = State(0, "")
    outcome := widened(var state)
    expect_false(outcome.is_ok())?

    cause := outcome.err()
    expect_equal(cause.message, "failed")?
    expect_equal(cause.details["code"], "42")?
    expect_equal(state.calls, 1)?

test "standalone in? closure returns from that closure":
    callback := fn() Unit!Failure:
        var inner = State(0, "")
        if true: operation(var inner, fail: true)?
        return ok(unit)

    outcome := callback()
    expect_false(outcome.is_ok())?
    expect_equal(outcome.err().code, 42)?
