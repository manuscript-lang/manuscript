import List from "@std/collections.ms"
import Decimal from "@std/decimal.ms"
import Result from "@std/result.ms"
import map_error from "@std/result.ms"

fn amount() -> Result[Decimal, String]:
    return ok(value: 12.50d)

test "explicit standard imports":
    assert [1, 2].length() == 2
    let outcome = map_error(
        result: amount(),
        transform: fn(cause: String) -> Int:
            return cause.byte_length()
    )
    match outcome:
        ok(value):
            assert value == 12.50d
        error(_):
            assert false
