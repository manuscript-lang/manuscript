# conform: tags=diagnostics,faults,modules,sets,stdlib-testing,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/preferred_names/conformance_test.ms
from "@std/test.ms" import expect_equal, expect_false
from "./domain.ms" import Key
from "./first.ms" import first_run, first_add, first_remove
from "./second.ms" import second_run

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
    let add = first_add(items)
    let remove = first_remove(items)
    add(Key(1, "original"))
    add(Key(1, "duplicate"))
    items.length() | try expect_equal(2)
    remove(Key(1, "different"))
    items.length() | try expect_equal(2)
    remove(Key(1, "original"))
    items.length() | try expect_equal(1)
