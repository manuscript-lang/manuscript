# conform: tags=closures,control-flow,diagnostics,faults,generics,interfaces,match,modules,stdlib-cleanup,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/local_extensions/second.ms
from "@std/test.ms" import expect_equal, expect_false
from "./domain.ms" import Item, Box, Holder, Choice
from "./contracts.ms" import Read, invoke, relay, as_view
from "@std/core.ms" import Closeable
from "@std/collections.ms" import ListBuilder

impl Read[Int] for Item:
    def get() -> Int:
        return self.original() + delta()

def delta() -> Int:
    return 20

impl Read[T] for Box[T]:
    def get() -> T:
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

export def second_view(value: Item) -> Read[Int]:
    return Read[Int](value)

export def second_method(value: Item) -> Callable[[], Int]:
    return value.get

export def second_generic() -> Callable[[Item], Int]:
    return relay[Item]

test "second local extensions":
    let item = Item(2)
    (item.get() != 22 or invoke(item) != 22 or relay(item) != 22) | try expect_false
    as_view(item).get() | try expect_equal(22)

    let holder = Holder(item)
    (holder.get() != 22 or invoke(holder) != 22 or holder.extract() != 22) | try expect_false
    Box("hello").get() | try expect_equal("hello")
    Choice.Some(2).get() | try expect_equal(22)

from "./domain.ms" import Resource

impl Closeable for Resource:
    def close() -> Unit:
        self.events.append(value: 20)

def leave(resource: Resource) -> Unit:
    let _local = resource
    return

export def second_resource(resource: Resource) -> Closeable:
    return Closeable(resource)

test "second local cleanup":
    let events = ListBuilder[Int]()
    leave(Resource(events))
    events.build().get(index: 0) | try expect_equal(20)

from "./first.ms" import mixed

test "generic evidence does not change concrete lexical dispatch":
    let item = Item(2)
    mixed(value: item, concrete: item) | try expect_equal(34)
