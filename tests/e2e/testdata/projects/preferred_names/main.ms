import Key from "./domain.ms"
import {first_run, first_add, first_remove} from "./first.ms"
import second_run from "./second.ms"
import Set from "@std/collections.ms"
import panic from "@std/faults.ms"

test "direct bound and forwarded calls retain defining equality scopes":
    let first = first_run().values()
    let second = second_run().values()
    if first.length() != 1 or first.at(0).unwrap().id != 2:
        return panic("first equality scope")
    if (
        second.length() != 1
        or second.at(0).unwrap().id != 1
        or second.at(0).unwrap().label != "original"
    ):
        return panic("second scope or original payload")

    let items = Set[Key]()
    let add = first_add(items)
    let remove = first_remove(items)
    add(Key(1, "original"))
    add(Key(1, "duplicate"))
    if items.length() != 1 or items.values().at(0).unwrap().label != "original":
        return panic("returned bound add scope")

    remove(Key(1, "different"))
    if not items.is_empty(): return panic("returned bound remove scope")
