import panic from "@std/faults.ms"

import {
    List,
    Map,
} from "@std/collections.ms"
import { Result, map_error } from "@std/result.ms"

fn describe(cause: Int) -> String:
    return "{cause}"

test "grouped imports":
    let values: List[Int] = [1, 2]
    let entries = Map[String, Int]().with_entry(key: "count", value: values.length())
    if not (entries.length() == 1):
        return panic(message: "check failed")
    let failure: Result[Int, Int] = error(cause: 3)
    let changed = map_error(result: failure, transform: describe)
    match changed:
        ok(value):
            if not (false):
                return panic(message: "check failed")
        error(cause):
            if not (cause == "3"):
                return panic(message: "check failed")
