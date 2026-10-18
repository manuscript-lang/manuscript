import panic from "@std/faults.ms"

fn map_total(values: Map[String, Int]) Int:
    var total = 0

    for entry in values:
        let {value} = entry
        total += value

    return total

fn set_total(values: Set[Int]) Int:
    var total = 0
    for value in values:
        total += value
    return total

test "map entry type":
    let entry = MapEntry[String, Int]("a", 3)
    if not (entry.key == "a"):
        return panic("check failed")
    if not (entry.value == 3):
        return panic("check failed")
