import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"

type Callback:
    handler: fn(value: Int) Int

fn increment(value: Int) Int:
    return value + 1

fn preserve_key[K: Hashable](value: K) K:
    return value

test "derived value equality":
    let present: Optional[Int] = some(1)
    let same: Optional[Int] = some(1)
    let missing: Optional[Int] = none
    if not (present == same):
        return panic("check failed")
    if not (present != missing):
        return panic("check failed")
    if not (1.00d == 1d):
        return panic("check failed")
    if not ([1, 2] == [1, 2]):
        return panic("check failed")
    if not ([1, 2] != [2, 1]):
        return panic("check failed")
    if not (preserve_key("key") == "key"):
        return panic("check failed")

    let _callback = Callback(increment)
