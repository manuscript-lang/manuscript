import panic from "@std/faults.ms"

test "grouped imports":
    let values: List[Int] = [1, 2]
    let entries = Map[String, Int]().add("count", values.length())
    if not (entries.length() == 1):
        return panic("check failed")
