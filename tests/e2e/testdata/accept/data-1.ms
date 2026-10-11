import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"

fn positives(values: List[Int]) -> List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result = result.append(value: value)
    return result

test "dynamic immutable data":
    assert positives(values: [3, -1, 2]) == [3, 2]
    let absent: Optional[Int] = none
    assert [1].get(index: 5) == absent
    let original = Map[String, Int]().with_entry(key: "a", value: 1)
    let updated = original.with_entry(key: "b", value: 2).with_entry(key: "a", value: 3)
    assert original.get(key: "a") == some(value: 1)
    assert updated.get(key: "a") == some(value: 3)
