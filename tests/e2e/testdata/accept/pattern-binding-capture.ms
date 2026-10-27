from "@std/test.ms" import expect_equal, expect_false

type Failure[T]:
    case NotFound
    case Denied(reason: T)

impl Error for Failure[T]:
    def message() -> String: "Failure"

# An advisory preserves the semantics of this fresh, capitalized binding.
def captured[T](result: Result[Int, Failure[T]]) -> Int:
    match result:
        case error(NotFound): return 1
        case ok(value): return value

def failure_code[T](cause: Failure[T]) -> Int:
    match cause:
        case NotFound: return 1
        case Denied(_): return 2

def precise[T](result: Result[Int, Failure[T]]) -> Int:
    match result:
        case error(cause): return failure_code(cause)
        case ok(value): return value

def failure_reason(cause: Failure[String]) -> String:
    match cause:
        case NotFound: return "missing"
        case Denied(reason): return reason

def deliberate(result: Result[Int, Failure[String]]) -> String:
    match result:
        case error(cause): return failure_reason(cause)
        case ok(_): return "ok"

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
