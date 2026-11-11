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
	return 20

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

export fn second_view(value: Item) Read[Int]:
	return value

export fn second_method(value: Item) fn() Int:
	return value.get

export fn second_generic() fn(Item) Int:
	return relay[Item]

test "second local extensions":
	item := Item(2)
	(
		(
			item.get() != 22
			or invoke(item) != 22
			or relay(item.clone()) != 22
		) | try expect_false
	)
	as_view(item).get() | try expect_equal(22)

	holder := Holder(item)
	(
		(
			holder.get() != 22
			or invoke(holder) != 22
			or holder.extract() != 22
		) | try expect_false
	)
	Box("hello").get() | try expect_equal("hello")
	Choice.Some(2).get() | try expect_equal(22)

import Resource from "./domain.ms"

impl Closeable for Resource:
	var fn close() Unit!:
		_ := append_file(self.events, "20,").wait()

fn leave(resource: Resource) Unit:
	_local := resource
	return

export fn second_resource(resource: Resource) Closeable:
	return resource

test "second local cleanup":
	dir := temporary("ms-ext-") | try expect_ok
	events := "{dir.path()}/events"
	leave(Resource(events.clone()))
	(try expect_ok(read_file(events).wait())).decode_utf8() | try expect_equal("20,")

import mixed from "./first.ms"

test "generic evidence does not change concrete lexical dispatch":
	item := Item(2)
	mixed(value: item, concrete: item) | try expect_equal(34)
