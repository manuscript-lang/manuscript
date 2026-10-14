import {Item, Box, Holder, Choice} from "./domain.ms"
import {Read, invoke, relay, as_view} from "./contracts.ms"
import Closeable from "@std/cleanup.ms"
import ListBuilder from "@std/collections.ms"
import panic from "@std/faults.ms"

impl Read[Int] for Item:
    fn get() -> Int:
        return self.original() + delta()

fn delta() -> Int:
    return 20

impl Read[T] for Box[T]:
    fn get() -> T:
        return self.value

impl Read[Int] for Choice:
    fn get() -> Int:
        match self:
            Some(value):
                return value + delta()

            Empty:
                return delta()

# A local interface can use the receiver's inherited bound.
interface Extract:
    fn extract() -> Int

impl Extract for Holder[T]:
    fn extract() -> Int:
        return self.value.get()

export fn second_view(value: Item) -> Read[Int]:
    return Read[Int](value)

export fn second_method(value: Item) -> fn() -> Int:
    return value.get

export fn second_generic() -> fn(value: Item) -> Int:
    return relay[Item]

test "second local extensions":
    let item = Item(2)
    if (
        item.get() != 22
        or invoke(item) != 22
        or relay(item) != 22
    ):
        return panic("local dispatch")
    if as_view(item).get() != 22:
        return panic("generic view")

    let holder = Holder(item)
    if (
        holder.get() != 22
        or invoke(holder) != 22
        or holder.extract() != 22
    ):
        return panic("nested generic dispatch")
    if Box("hello").get() != "hello":
        return panic("generic extension")
    if Choice.Some(2).get() != 22:
        return panic("alternative extension")

import Resource from "./domain.ms"

impl Closeable for Resource:
    fn close() -> Unit:
        self.events.append(value: 20)

fn leave(resource: Resource) -> Unit:
    with local = resource:
        return

export fn second_resource(resource: Resource) -> Closeable:
    return Closeable(resource)

test "second local cleanup":
    let events = ListBuilder[Int]()
    leave(Resource(events))
    if events.freeze().at(index: 0) != some(20):
        return panic("local cleanup")

import mixed from "./first.ms"

test "generic evidence does not change concrete lexical dispatch":
    let item = Item(2)
    if mixed(value: item, concrete: item) != 34:
        return panic("generic evidence changed concrete dispatch")
