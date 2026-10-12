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
    assert entries.length() == 1
    let failure: Result[Int, Int] = error(cause: 3)
    let changed = map_error(result: failure, transform: describe)
    match changed:
        ok(value):
            assert false
        error(cause):
            assert cause == "3"
