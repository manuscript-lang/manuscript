import expect_equal, expect_false, expect_ok from "@std/test/test.ms"
import first_view, first_method, first_generic, first_resource from "./first.ms"
import second_view, second_method, second_generic, second_resource from "./second.ms"
import Item, Resource from "./domain.ms"
import read_view from "./contracts.ms"
import read_file, temporary from "@std/os/fs.ms"

fn close_first(resource: Resource) Unit:
    let _held = first_resource(resource)

fn close_second(resource: Resource) Unit:
    let _held = second_resource(resource)

test "views and functions retain local implementations across modules":
    let item = Item(2)
    item.original() | try expect_equal(2)

    let first = first_view(item)
    let second = second_view(item)
    (first.get() != 12 or second.get() != 22) | try expect_false
    try expect_false((read_view(first) != 12 or read_view(second) != 22))

    // A returned method value owns its receiver, so each call takes a clone.
    let first_call = first_method(item.clone())
    let second_call = second_method(item.clone())
    (first_call() != 12 or second_call() != 22) | try expect_false

    let first_fn = first_generic()
    let second_fn = second_generic()
    (first_fn(item) != 12 or second_fn(item) != 22) | try expect_false

    let dir = temporary("ms-ext-") | try expect_ok
    let events = "{dir.path()}/events"
    let resource = Resource(events.clone())

    // Each `Closeable` closes through its own module's implementation when its scope ends.
    close_first(Resource(events.clone()))
    close_second(resource)
    (try expect_ok(read_file(events).wait())).decode_utf8() | try expect_equal("10,20,")
