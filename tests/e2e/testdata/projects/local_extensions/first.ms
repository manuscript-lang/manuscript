import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok from "@std/test/test.ms",

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
		return self.value.clone()

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
	(item.get() != 12 or invoke(item) != 12 or relay(item.clone()) != 12) | expect_false?
	as_view(item).get() | expect_equal(12)?

	holder := Holder(item)
	(holder.get() != 12 or invoke(holder) != 12 or holder.extract() != 12) | expect_false?
	Box("hello").get() | expect_equal("hello")?
	Choice.Some(2).get() | expect_equal(12)?

import Resource from "./domain.ms"

impl Closeable for Resource:
	var fn close() Unit!:
		_ := append_file(self.events, "10,").wait()

fn leave(resource: Resource) Unit:
	_local := resource
	return

export fn first_resource(resource: Resource) Closeable:
	return resource

test "first local cleanup":
	dir := temporary("ms-ext-") | expect_ok?
	events := "{dir.path()}/events"
	leave(Resource(events.clone()))
	(expect_ok(read_file(events).wait())?).decode_utf8() | expect_equal("10,")?

export fn mixed[T: Read[Int]](value: T, concrete: Item) Int:
	return value.get() + concrete.get()
