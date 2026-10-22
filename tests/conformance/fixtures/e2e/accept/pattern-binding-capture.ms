# conform: tags=alternatives,control-flow,generics,interfaces,match,modules,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/pattern-binding-capture.ms
import {expect_equal, expect_false} from "@std/testing.ms"

type Failure[T]:
    case NotFound
    case Denied(reason: T)

impl Error for Failure[T]:
    fn message() String: "Failure"

# An advisory preserves the semantics of this fresh, capitalized binding.
fn captured[T](result: Result[Int, Failure[T]]) Int:
    match result:
        error(NotFound): return 1
        ok(value): return value

fn failure_code[T](cause: Failure[T]) Int:
    match cause:
        NotFound: return 1
        Denied(_): return 2

fn precise[T](result: Result[Int, Failure[T]]) Int:
    match result:
        error(cause): return failure_code(cause)
        ok(value): return value

fn failure_reason(cause: Failure[String]) String:
    match cause:
        NotFound: return "missing"
        Denied(reason): return reason

fn deliberate(result: Result[Int, Failure[String]]) String:
    match result:
        error(cause): return failure_reason(cause)
        ok(_): return "ok"

test "a payload identifier binds every alternative without changing semantics":
    let denied: Result[Int, Failure[String]] = error(
        Failure[String].Denied("permission denied")
    )
    let missing: Result[Int, Failure[String]] = error(Failure[String].NotFound)
    let success: Result[Int, Failure[String]] = ok(7)
    try expect_false(
        (
            captured(denied.clone()) != 1
            or captured(missing.clone()) != 1
            or captured(success.clone()) != 7
        )
    )
    try expect_false(
        (
            precise(denied.clone()) != 2
            or precise(missing) != 1
            or precise(success) != 7
        )
    )
    try expect_equal(deliberate(denied), "permission denied")
