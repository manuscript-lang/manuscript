import Key from "./key.ms"
import {
    id_map,
    id_direct,
    id_bound,
    id_generic,
    id_returned
} from "./by_id.ms"
import {label_map, label_direct, label_bound, label_generic} from "./by_label.ms"
import panic from "@std/faults.ms"

test "Map removal keeps direct bound generic and defining-module key scopes":
    let first = id_map()
    id_direct(first, Key(1, "different"))
    id_bound(first, Key(2, "different"))
    id_generic(first, Key(3, "different"))
    if not first.is_empty: return panic("id scope")

    let second = label_map()
    label_direct(second, Key(99, "one"))
    label_bound(second, Key(99, "two"))
    label_generic(second, Key(99, "three"))
    if not second.is_empty: return panic("label scope")

    let returned_values = id_map()
    let remove = id_returned(returned_values)
    remove(Key(1, "different"))
    if returned_values.length != 2 or returned_values.keys() [0].unwrap().id != 2:
        return panic("returned bound scope or order")
