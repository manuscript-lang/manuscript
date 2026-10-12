import panic from "@std/faults.ms"

import {
    List,
    Map,
} from "@std/collections.ms"

test "grouped imports":
    let values: List[Int] = [1, 2]
    let entries = Map[String, Int]().with_entry(key: "count", value: values.length())
    if not (entries.length() == 1):
        return panic(message: "check failed")
