# conform: tags=closures,control-flow,faults,formatter,generics,interfaces,match,modules,parser,stdlib-cleanup,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/local_extensions/second.ms
import {expect_equal, expect_false} from "@std/testing.ms"
import {Item, Box, Holder, Choice} from "./domain.ms"
import {Read, invoke, relay, as_view} from "./contracts.ms"
import Closeable from "@std/core.ms"
import ListBuilder from "@std/collections.ms"

impl Read[Int] for Item:
    fn get() Int:
        return self.original() + delta()

fn delta() Int:
    return 20

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

export fn second_view(value: Item) Read[Int]:
    return Read[Int](value)

export fn second_method(value: Item) fn() Int:
    return value.get

export fn second_generic() fn(value: Item) Int:
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
    fn close() Unit:
        self.events.append(value: 20)

fn leave(resource: Resource) Unit:
    with local = resource:
        return

export fn second_resource(resource: Resource) Closeable:
    return Closeable(resource)

test "second local cleanup":
    let events = ListBuilder[Int]()
    leave(Resource(events))
    events.freeze().get(index: 0) | try expect_equal(20)

import mixed from "./first.ms"

test "generic evidence does not change concrete lexical dispatch":
    let item = Item(2)
    mixed(value: item, concrete: item) | try expect_equal(34)
