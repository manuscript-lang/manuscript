import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Decimal from "@std/decimal.ms"
import Optional from "@std/optional.ms"

type Callback:
    handler: fn(value: Int) -> Int

fn increment(value: Int) -> Int:
    return value + 1

fn preserve_key[K: Hashable](value: K) -> K:
    return value

test "derived value equality":
    let present: Optional[Int] = some(value: 1)
    let same: Optional[Int] = some(value: 1)
    let missing: Optional[Int] = none
    if not (present == same):
        return panic(message: "check failed")
    if not (present != missing):
        return panic(message: "check failed")
    if not (1.00d == 1d):
        return panic(message: "check failed")
    if not ([1, 2] == [1, 2]):
        return panic(message: "check failed")
    if not ([1, 2] != [2, 1]):
        return panic(message: "check failed")
    if not (preserve_key(value: "key") == "key"):
        return panic(message: "check failed")

    let callback = Callback(handler: increment)
