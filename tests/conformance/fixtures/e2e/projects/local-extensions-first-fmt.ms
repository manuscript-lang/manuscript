// conform: tags=closures,control-flow,faults,formatter,generics,interfaces,match,modules,parser,stdlib-cleanup,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/projects/local_extensions/first.ms
import (
	share from "@std/concurrency/shared.ms",
	lock from "@std/concurrency/sync.ms",
	Closeable from "@std/core.ms",
	expect_equal, expect_false from "@std/test/test.ms",

	Read, as_view, invoke, relay from "./contracts.ms",
	Box, Choice, Holder, Item from "./domain.ms",
)

impl Read[Int] for Item:
	fn get() Int:
		return self.original() + delta()

fn delta() Int:
	return 10

impl Read[T] for Box[T]:
	fn get() T:
		return self.value

impl Read[Int] for Choice:
	fn get() Int:
		match self:
			Some(value):
				return value + delta()
			Empty:
				return delta()

// A local interface can use the receiver's inherited bound.
interface Extract:
	fn extract() Int

impl Extract for Holder[T]:
	fn extract() Int:
		return self.value.get()

export fn first_view(value: Item) Read[Int]:
	return value

export fn first_method(value: Item) fn() Int:
	return value.get

export fn first_generic() fn(Item) Int:
	return relay[Item]

test "first local extensions":
	item := Item(2)
	(item.get() != 12 or invoke(item) != 12 or relay(item) != 12) | expect_false?
	as_view(item).get() | expect_equal(12)?

	holder := Holder(item)
	(holder.get() != 12 or invoke(holder) != 12 or holder.extract() != 12) | expect_false?
	Box("hello").get() | expect_equal("hello")?
	Choice.Some(2).get() | expect_equal(12)?

import Resource from "./domain.ms"

impl Closeable for Resource:
	var fn close() Unit!:
		var guard = lock(self.events)
		guard.value.append(value: 10)

fn leave(resource: Resource) Unit:
	_local := resource
	return

export fn first_resource(resource: Resource) Closeable:
	return resource

test "first local cleanup":
	events := share(List[Int]())
	leave(Resource(events))
	events.get().get(index: 0) | expect_equal(10)?

export fn mixed[T: Read[Int]](value: T, concrete: Item) Int:
	return value.get() + concrete.get()
