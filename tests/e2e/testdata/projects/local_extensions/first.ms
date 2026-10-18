import {expect_equal, expect_false} from "@std/testing.ms"
import {Item, Box, Holder, Choice} from "./domain.ms"
import {Read, invoke, relay, as_view} from "./contracts.ms"
import Closeable from "@std/cleanup.ms"
import ListBuilder from "@std/collections.ms"

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

# A local interface can use the receiver's inherited bound.
interface Extract:
    fn extract() Int

impl Extract for Holder[T]:
    fn extract() Int:
        return self.value.get()

export fn first_view(value: Item) Read[Int]:
    return Read[Int](value)

export fn first_method(value: Item) fn() Int:
    return value.get

export fn first_generic() fn(value: Item) Int:
    return relay[Item]

test "first local extensions":
    let item = Item(2)
    (item.get() != 12 or invoke(item) != 12 or relay(item) != 12) | try expect_false
    as_view(item).get() | try expect_equal(expected: 12)
    let holder = Holder(item)
    (holder.get() != 12 or invoke(holder) != 12 or holder.extract() != 12) | try expect_false
    Box("hello").get() | try expect_equal(expected: "hello")
    Choice.Some(2).get() | try expect_equal(expected: 12)

import Resource from "./domain.ms"

impl Closeable for Resource:
    fn close() Unit:
        self.events.append(value: 10)

fn leave(resource: Resource) Unit:
    with local = resource:
        return

export fn first_resource(resource: Resource) Closeable:
    return Closeable(resource)

test "first local cleanup":
    let events = ListBuilder[Int]()
    leave(Resource(events))
    events.freeze().get(index: 0) | try expect_equal(expected: 10)

export fn mixed[T: Read[Int]](value: T, concrete: Item) Int:
    return value.get() + concrete.get()
