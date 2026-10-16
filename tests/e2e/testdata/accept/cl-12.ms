import panic from "@std/faults.ms"

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
    if not (entry.key == "a"):
        return panic(message: "check failed")
    if not (entry.value == 3):
        return panic(message: "check failed")
