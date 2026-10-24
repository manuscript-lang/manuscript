from "@std/testing.ms" import expect_equal, expect_false
from "./domain.ms" import Item, Box, Holder, Choice
from "./contracts.ms" import Read, invoke, relay, as_view
from "@std/core.ms" import Closeable
from "@std/collections.ms" import ListBuilder

impl Read[Int] for Item:
    def get() -> Int:
        return self.original() + delta()

def delta() -> Int:
    return 10

impl Read[T] for Box[T]:
    def get() -> ref T:
        return self.value

impl Read[Int] for Choice:
    def get() -> Int:
        match self:
            case Some(value):
                return value + delta()
            case Empty:
                return delta()

# A local interface can use the receiver's inherited bound.
interface Extract:
    def extract() -> Int

impl Extract for Holder[T]:
    def extract() -> Int:
        return self.value.get()

export def first_view(value: Item) -> Read[Int]:
    return value

export def first_method(value: Item) -> Callable[[], Int]:
    return value.get

export def first_generic() -> Callable[[Item], Int]:
    return relay[Item]

test "first local extensions":
    let item = Item(2)
    (item.get() != 12 or invoke(item) != 12 or relay(item) != 12) | try expect_false
    as_view(item).get() | try expect_equal(12)

    let holder = Holder(item)
    (holder.get() != 12 or invoke(holder) != 12 or holder.extract() != 12) | try expect_false
    Box("hello").get() | try expect_equal("hello")
    Choice.Some(2).get() | try expect_equal(12)

from "./domain.ms" import Resource

impl Closeable for Resource:
    var def close() -> Unit:
        self.events.append(value: 10)

def leave(resource: Resource) -> Unit:
    with resource as local:
        return

export def first_resource(resource: Resource) -> Closeable:
    return resource

test "first local cleanup":
    var events = ListBuilder[Int]()
    leave(Resource(events))
    events.freeze().get(index: 0) | try expect_equal(10)

export def mixed[T: Read[Int]](value: T, concrete: Item) -> Int:
    return value.get() + concrete.get()
