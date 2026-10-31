import expect_equal, expect_false from "@std/test.ms"
import Item, Box, Holder, Choice from "./domain.ms"
import Read, invoke, relay, as_view from "./contracts.ms"
import Closeable from "@std/core.ms"
import share from "@std/shared.ms"
import lock from "@std/sync.ms"

impl Read[Int] for Item:
    fn get() Int:
        return self.original() + delta()

fn delta() Int:
    return 20

impl Read[T] for Box[T]:
    fn get() ref T:
        return self.value

impl Read[Int] for Choice:
    fn get() Int:
        match self:
            Some(value):
                return value + delta()
            Empty:
                return delta()

# A local interface can use the receiver's inherited bound.
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
    let item = Item(2)
    (item.get() != 22 or invoke(item) != 22 or relay(item) != 22) | try expect_false
    as_view(item).get() | try expect_equal(22)

    let holder = Holder(item)
    (holder.get() != 22 or invoke(holder) != 22 or holder.extract() != 22) | try expect_false
    Box("hello").get() | try expect_equal("hello")
    Choice.Some(2).get() | try expect_equal(22)

import Resource from "./domain.ms"

impl Closeable for Resource:
    var fn close() Unit!:
        var guard = lock(self.events)
        guard.value.append(value: 20)
        return ok(unit)

fn leave(resource: Resource) Unit:
    let _local = resource
    return

export fn second_resource(resource: Resource) Closeable:
    return resource

test "second local cleanup":
    let events = share(List[Int]())
    leave(Resource(events))
    events.get().get(index: 0) | try expect_equal(20)

import mixed from "./first.ms"

test "generic evidence does not change concrete lexical dispatch":
    let item = Item(2)
    mixed(value: item, concrete: item) | try expect_equal(34)
