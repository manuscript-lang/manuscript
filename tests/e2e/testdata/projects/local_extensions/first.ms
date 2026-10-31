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

# A local interface can use the receiver's inherited bound.
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
    let item = Item(2)
    (item.get() != 12 or invoke(item) != 12 or relay(item) != 12) | try expect_false
    as_view(item).get() | try expect_equal(12)

    let holder = Holder(item)
    (holder.get() != 12 or invoke(holder) != 12 or holder.extract() != 12) | try expect_false
    Box("hello").get() | try expect_equal("hello")
    Choice.Some(2).get() | try expect_equal(12)

import Resource from "./domain.ms"

impl Closeable for Resource:
    var fn close() Unit!:
        var guard = lock(self.events)
        guard.value.append(value: 10)
        return ok(unit)

fn leave(resource: Resource) Unit:
    let _local = resource
    return

export fn first_resource(resource: Resource) Closeable:
    return resource

test "first local cleanup":
    let events = share(List[Int]())
    leave(Resource(events))
    events.get().get(index: 0) | try expect_equal(10)

export fn mixed[T: Read[Int]](value: T, concrete: Item) Int:
    return value.get() + concrete.get()
