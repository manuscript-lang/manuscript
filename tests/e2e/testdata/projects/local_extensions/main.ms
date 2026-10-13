import {first_view, first_method, first_generic, first_resource} from "./first.ms"
import {second_view, second_method, second_generic, second_resource} from "./second.ms"
import {Item, Resource} from "./domain.ms"
import {Read, read_view} from "./contracts.ms"
import ListBuilder from "@std/collections.ms"
import Optional from "@std/optional.ms"
import panic from "@std/faults.ms"

test "views and functions retain local implementations across modules":
    let item = Item(2)
    if item.original() != 2:
        return panic("original implementation")

    let first = first_view(item)
    let second = second_view(item)
    if first.get() != 12 or second.get() != 22:
        return panic("returned views")
    if (
        read_view(Read[Int](first)) != 12
        or read_view(Read[Int](second)) != 22
    ):
        return panic("view conversion changed implementation")

    let first_call = first_method(item)
    let second_call = second_method(item)
    if first_call() != 12 or second_call() != 22:
        return panic("bound methods")

    let first_fn = first_generic()
    let second_fn = second_generic()
    if first_fn(item) != 12 or second_fn(item) != 22:
        return panic("specialized functions")

    let events = ListBuilder[Int]()
    let resource = Resource(events)

    with first_close = first_resource(resource):
        let active = true

    with second_close = second_resource(resource):
        let active = true

    let values = events.freeze()
    if values.at(index: 0) != some(10) or values.at(index: 1) != some(20):
        return panic("cleanup views")
