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
    assert present == same
    assert present != missing
    assert 1.00d == 1d
    assert [1, 2] == [1, 2]
    assert [1, 2] != [2, 1]
    assert preserve_key(value: "key") == "key"
    let callback = Callback(handler: increment)
