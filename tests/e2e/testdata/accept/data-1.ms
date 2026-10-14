import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"

fn positives(values: List[Int]) -> List[Int]:
    var result: List[Int] = []

    for value in values:
        if value > 0:
            result = result.append(value: value)

    return result

test "dynamic mutable data and explicit copies":
    if not (positives(values: [3, -1, 2]) == [3, 2]):
        return panic(message: "check failed")

    let absent: Optional[Int] = none
    if not ([1].at(index: 5) == absent):
        return panic(message: "check failed")

    let original = Map[String, Int]().add(key: "a", value: 1)
    let updated = (
        original
        .clone()
        .add(key: "b", value: 2)
        .add(key: "a", value: 3)
    )
    if not (original.get(key: "a") == some(1)):
        return panic(message: "check failed")
    if not (updated.get(key: "a") == some(3)):
        return panic(message: "check failed")
