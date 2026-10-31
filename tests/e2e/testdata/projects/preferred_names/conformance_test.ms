import expect_equal, expect_false, expect_true from "@std/test.ms"
import Key from "./domain.ms"
import first_run, first_add, first_remove, first_empty from "./first.ms"
import second_run from "./second.ms"

test "bound and forwarded calls keep the equality of the collection creator":
    let first = first_run().values()
    let second = second_run().values()
    (first.length() != 1 or first.get(0).id != 2) | try expect_false
    try expect_false(
        (
            second.length() != 1
            or second.get(0).id != 1
            or second.get(0).label != "original"
        )
    )

    # A collection keeps the equality of the module that created it, so
    # bound operations from another module do not change how it matches.
    var items = Set[Key]()
    first_add(var items, Key(1, "original"))
    first_add(var items, Key(1, "duplicate"))
    items.length() | try expect_equal(2)
    first_remove(var items, Key(1, "different"))
    items.length() | try expect_equal(2)
    first_remove(var items, Key(1, "original"))
    items.length() | try expect_equal(1)

test "Set construction clone and clear keep creator evidence across modules":
    var items = first_run()
    items.contains(Key(2, "different")) | try expect_true

    var copied = items.clone()
    copied.clear()

    var empty_copy = copied.clone()
    empty_copy.add(Key(7, "first"))
    empty_copy.add(Key(7, "second"))
    empty_copy.length() | try expect_equal(1)
    empty_copy.remove(Key(7, "third"))
    empty_copy.is_empty() | try expect_true

    var structural = Set[Key]([])
    first_add(var structural, Key(1, "first"))
    first_add(var structural, Key(1, "second"))
    structural.length() | try expect_equal(2)

test "An empty returned Set keeps the constructor descriptor":
    var items = first_empty()
    items.add(Key(1, "first"))
    items.add(Key(1, "second"))
    items.length() | try expect_equal(1)
    items.contains(Key(1, "third")) | try expect_true

test "Set algebra retains the left creator evidence in another module":
    let items = first_run()
    var united = items.union(items)
    united.add(Key(2, "different"))
    united.length() | try expect_equal(1)

    var common = items.intersection(items)
    common.remove(Key(2, "different"))
    common.is_empty() | try expect_true

    var absent = items.difference(items)
    absent.add(Key(7, "first"))
    absent.add(Key(7, "second"))
    absent.length() | try expect_equal(1)
