import Key from "./domain.ms"
import {first_run, first_add, first_remove} from "./first.ms"
import second_run from "./second.ms"
import panic from "@std/faults.ms"

test "bound and forwarded calls keep the equality of the collection creator":
    let first = first_run().values()
    let second = second_run().values()
    if first.length() != 1 or first.at(0).get().id != 2:
        return panic("first equality scope")
    if (
        second.length() != 1
        or second.at(0).get().id != 1
        or second.at(0).get().label != "original"
    ):
        return panic("second scope or original payload")

    # A collection keeps the equality of the module that created it, so
    # bound operations from another module do not change how it matches.
    let items = Set[Key]()
    let add = first_add(items)
    let remove = first_remove(items)
    add(Key(1, "original"))
    add(Key(1, "duplicate"))
    if items.length() != 2: return panic("collection equality follows its creator")

    remove(Key(1, "different"))
    if items.length() != 2: return panic("remove matches with the creator's equality")

    remove(Key(1, "original"))
    if items.length() != 1: return panic("remove with the creator's equality")
