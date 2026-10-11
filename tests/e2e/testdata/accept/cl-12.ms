import Map from "@std/collections.ms"
import MapEntry from "@std/collections.ms"
import Set from "@std/collections.ms"

fn map_total(values: Map[String, Int]) -> Int:
    var total = 0
    for entry in values:
        let {key, value} = entry
        let label: String = key
        total = total + value
    return total

fn set_total(values: Set[Int]) -> Int:
    var total = 0
    for value in values:
        total = total + value
    return total

test "map entry type":
    let entry = MapEntry[String, Int](key: "a", value: 3)
    assert entry.key == "a"
    assert entry.value == 3
