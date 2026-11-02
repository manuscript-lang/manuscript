# conform: tags=closures,diagnostics,faults,modules,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/local_extensions/conformance_test.ms
import expect_equal, expect_false from "@std/test/test.ms"
import first_view, first_method, first_generic, first_resource from "./first.ms"
import second_view, second_method, second_generic, second_resource from "./second.ms"
import Item, Resource from "./domain.ms"
import Read, read_view from "./contracts.ms"
import share from "@std/concurrency/shared.ms"

test "views and functions retain local implementations across modules":
    let item = Item(2)
    item.original() | try expect_equal(2)

    let first = first_view(item)
    let second = second_view(item)
    (first.get() != 12 or second.get() != 22) | try expect_false
    try expect_false((read_view(first) != 12 or read_view(second) != 22))

    let first_call = first_method(item)
    let second_call = second_method(item)
    (first_call() != 12 or second_call() != 22) | try expect_false

    let first_fn = first_generic()
    let second_fn = second_generic()
    (first_fn(item) != 12 or second_fn(item) != 22) | try expect_false

    let events = share(List[Int]())
    let resource = Resource(events)
    var _first_close = first_resource(Resource(events))
    let _active = true
    _first_close.close()

    var _second_close = second_resource(resource)
    let _second_active = true
    _second_close.close()

    let values = events.get()
    (values.get(index: 0) != 10 or values.get(index: 1) != 20) | try expect_false
