import panic from "@std/faults.ms"

type Failure:
    message_text: String

impl Error for Failure:
    fn message() String:
        return self.message_text

fn success() Result[Optional[Int], Error]:
    return ok(some(7))

fn failure() Result[Int, Failure]:
    return error(Failure("failed"))

fn propagated() Result[Int, Error]:
    return ok(try failure())

test "prelude cases and optional methods need no imports":
    let inferred = some(3)
    let absent: Optional[Int] = none
    let qualified = Optional[Int].some(5)
    if not inferred.is_some() or not absent.is_none():
        return panic("presence check failed")
    if inferred.unwrap() != 3 or qualified.unwrap() != 5:
        return panic("payload changed")
    if absent.unwrap_or(9) != 9 or absent.unwrap_or_else(fn() Int: return 11) != 11:
        return panic("fallback failed")

    let value = try success()
    if value.unwrap() != 7: return panic("result payload changed")

test "prelude Error preserves concrete failures through try":
    let outcome = propagated()
    if not outcome.is_error(): return panic("failure did not propagate")

    let cause = outcome.unwrap_error()
    if cause.message() != "failed": return panic("error receiver lost")

    match cause:
        Failure(value):
            if value.message_text != "failed": return panic("error payload lost")
        _: return panic("concrete error lost")
