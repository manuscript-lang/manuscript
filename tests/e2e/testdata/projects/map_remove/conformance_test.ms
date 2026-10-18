import {expect_false, expect_true} from "@std/testing.ms"
import Key from "./key.ms"
import {id_map, id_direct, id_bound, id_generic, id_returned} from "./by_id.ms"
import {label_map, label_direct, label_bound, label_generic} from "./by_label.ms"

test "Map removal keeps direct bound generic and defining-module key scopes":
    let first = id_map()
    id_direct(first, Key(1, "different"))
    id_bound(first, Key(2, "different"))
    id_generic(first, Key(3, "different"))
    (first.is_empty()) | try expect_true
    let second = label_map()
    label_direct(second, Key(99, "one"))
    label_bound(second, Key(99, "two"))
    label_generic(second, Key(99, "three"))
    (second.is_empty()) | try expect_true
    let returned_values = id_map()
    let remove = id_returned(returned_values)
    remove(Key(1, "different"))
    try expect_false(
        (
            returned_values.length() != 2
            or returned_values.keys() [0].unwrap().id != 2
        )
    )
