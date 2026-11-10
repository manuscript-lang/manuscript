import (
    expect_equal, expect_false, expect_ok from "@std/test/test.ms",
    first_view, first_method, first_generic, first_resource from "./first.ms",
    second_view, second_method, second_generic, second_resource from "./second.ms",
    Item, Resource from "./domain.ms",
    read_view from "./contracts.ms",
    read_file, temporary from "@std/os/fs.ms",
)

fn close_first(resource: Resource) Unit:
    _held := first_resource(resource)

fn close_second(resource: Resource) Unit:
    _held := second_resource(resource)

test "views and functions retain local implementations across modules":
    item := Item(2)
    item.original() | try expect_equal(2)

    first := first_view(item)
    second := second_view(item)
    (first.get() != 12 or second.get() != 22) | try expect_false
    try expect_false((read_view(first) != 12 or read_view(second) != 22))

    // A returned method value owns its receiver, so each call takes a clone.
    first_call := first_method(item.clone())
    second_call := second_method(item.clone())
    (first_call() != 12 or second_call() != 22) | try expect_false

    first_fn := first_generic()
    second_fn := second_generic()
    (first_fn(item) != 12 or second_fn(item) != 22) | try expect_false

    dir := temporary("ms-ext-") | try expect_ok
    events := "{dir.path()}/events"
    resource := Resource(events.clone())

    // Each `Closeable` closes through its own module's implementation when its scope ends.
    close_first(Resource(events.clone()))
    close_second(resource)
    (try expect_ok(read_file(events).wait())).decode_utf8() | try expect_equal("10,20,")
