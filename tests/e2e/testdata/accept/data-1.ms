import panic from "@std/faults.ms"

fn positives(values: List[Int]) List[Int]:
    let result: List[Int] = []
    for value in values:
        if value > 0:
            result.append(value)
    return result

test "dynamic mutable data and explicit copies":
    if not (positives([3, -1, 2]) == [3, 2]):
        return panic("check failed")

    let absent: Optional[Int] = none
    if not ([1].at(5) == absent):
        return panic("check failed")

    let original = Map[String, Int]().add("a", 1)
    let updated = (original.clone().add("b", 2).add("a", 3))
    if not (original.get("a") == some(1)):
        return panic("check failed")
    if not (updated.get("a") == some(3)):
        return panic("check failed")
