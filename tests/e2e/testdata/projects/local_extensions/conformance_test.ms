import (
	read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok from "@std/test/test.ms",

	read_view from "./contracts.ms",
	Item, Resource from "./domain.ms",
	first_generic, first_method, first_resource, first_view from "./first.ms",
	second_generic, second_method, second_resource, second_view from "./second.ms",
)

fn close_first(resource: Resource) Unit:
	_held := first_resource(resource)

fn close_second(resource: Resource) Unit:
	_held := second_resource(resource)

test "views and functions retain local implementations across modules":
	item := Item(2)
	item.original() | expect_equal(2)?

	first := first_view(item)
	second := second_view(item)
	(first.get() != 12 or second.get() != 22) | expect_false?
	expect_false((read_view(first) != 12 or read_view(second) != 22))?

	// A returned method value owns its receiver, so each call takes a clone.
	first_call := first_method(item.clone())
	second_call := second_method(item.clone())
	(first_call() != 12 or second_call() != 22) | expect_false?

	first_fn := first_generic()
	second_fn := second_generic()
	(first_fn(item) != 12 or second_fn(item) != 22) | expect_false?

	dir := temporary("ms-ext-") | expect_ok?
	events := "{dir.path()}/events"
	resource := Resource(events.clone())

	// Each `Closeable` closes through its own module's implementation when its scope ends.
	close_first(Resource(events.clone()))
	close_second(resource)
	(expect_ok(read_file(events).wait())?).decode_utf8() | expect_equal("10,20,")?
