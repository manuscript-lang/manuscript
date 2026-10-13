import panic from "@std/faults.ms"

type Failure[T]:
    case NotFound
    case Denied(reason: T)

# An advisory preserves the semantics of this fresh, capitalized binding.
fn captured[T](result: Result[Int, Failure[T]]) -> Int:
    match result:
        error(NotFound): return 1
        ok(value): return value

fn precise[T](result: Result[Int, Failure[T]]) -> Int:
    match result:
        error(cause):
            match cause:
                NotFound: return 1
                Denied(_): return 2
        ok(value): return value

fn deliberate(result: Result[Int, Failure[String]]) -> String:
    match result:
        error(cause):
            match cause:
                NotFound: return "missing"
                Denied(reason): return reason
        ok(_): return "ok"

test "a payload identifier binds every alternative without changing semantics":
    let denied: Result[Int, Failure[String]] = error(
        Failure[String].Denied("permission denied")
    )
    let missing: Result[Int, Failure[String]] = error(Failure[String].NotFound)
    let success: Result[Int, Failure[String]] = ok(7)
    if (
        captured(denied) != 1
        or captured(missing) != 1
        or captured(success) != 7
    ):
        return panic(message: "payload binding semantics changed")
    if (
        precise(denied) != 2
        or precise(missing) != 1
        or precise(success) != 7
    ):
        return panic(message: "nested match did not distinguish alternatives")
    if deliberate(denied) != "permission denied":
        return panic(message: "bound error payload was lost")
