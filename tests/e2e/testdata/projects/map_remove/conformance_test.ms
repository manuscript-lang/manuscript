import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import Key from "./key.ms"
import id_map, id_direct, id_bound, id_generic, id_empty from "./by_id.ms"
import label_map, label_direct, label_bound, label_generic from "./by_label.ms"

test "Map removal keeps direct bound generic and defining-module key scopes":
    var first = id_map()
    id_direct(var first, Key(1, "different"))
    id_bound(var first, Key(2, "different"))
    id_generic(var first, Key(3, "different"))
    (first.is_empty()) | try expect_true

    var second = label_map()
    label_direct(var second, Key(99, "one"))
    label_bound(var second, Key(99, "two"))
    label_generic(var second, Key(99, "three"))
    (second.is_empty()) | try expect_true

    var returned_values = id_map()
    let remove = returned_values.remove
    remove(Key(1, "different"))
    try expect_false(
        (returned_values.length() != 2 or returned_values.keys()[0].id != 2)
    )

test "Map lookup clone and clear keep the creator key identity":
    var values = id_map()
    values.contains(Key(1, "different")) | try expect_true
    values.get(Key(2, "different")).get() | try expect_equal(20)

    let get = values.get
    get(Key(3, "different")).get() | try expect_equal(30)

    var copied = values.clone()
    copied.remove(Key(1, "different"))
    copied.length() | try expect_equal(2)
    values.length() | try expect_equal(3)
    copied.clear()

    var empty_copy = copied.clone()
    empty_copy.add(Key(7, "first"), 1)
    empty_copy.add(Key(7, "second"), 2)
    empty_copy.length() | try expect_equal(1)
    empty_copy.get(Key(7, "third")).get() | try expect_equal(2)

test "An empty returned Map keeps creator evidence before its first insertion":
    var values = id_empty()
    values.add(Key(1, "first"), 1)
    values.add(Key(1, "second"), 2)
    values.length() | try expect_equal(1)
    values.get(Key(1, "third")).get() | try expect_equal(2)
