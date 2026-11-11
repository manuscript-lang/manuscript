// conform: tags=closures,diagnostics,faults,modules,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/local_extensions/conformance_test.ms
import (
	share from "@std/concurrency/shared.ms",
	expect_equal, expect_false from "@std/test/test.ms",

	Read, read_view from "./contracts.ms",
	Item, Resource from "./domain.ms",
	first_generic, first_method, first_resource, first_view from "./first.ms",
	second_generic, second_method, second_resource, second_view from "./second.ms",
)

test "views and functions retain local implementations across modules":
	item := Item(2)
	item.original() | expect_equal(2)?

	first := first_view(item)
	second := second_view(item)
	(first.get() != 12 or second.get() != 22) | expect_false?
	expect_false((read_view(first) != 12 or read_view(second) != 22))?

	first_call := first_method(item)
	second_call := second_method(item)
	(first_call() != 12 or second_call() != 22) | expect_false?

	first_fn := first_generic()
	second_fn := second_generic()
	(first_fn(item) != 12 or second_fn(item) != 22) | expect_false?

	events := share(List[Int]())
	resource := Resource(events)
	var _first_close = first_resource(Resource(events))
	_active := true
	_first_close.close()

	var _second_close = second_resource(resource)
	_second_active := true
	_second_close.close()

	values := events.get()
	(values.get(index: 0) != 10 or values.get(index: 1) != 20) | expect_false?
