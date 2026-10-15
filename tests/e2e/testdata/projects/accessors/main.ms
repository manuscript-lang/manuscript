import {Item, Read, generic, invoke_observed} from "./domain.ms"
import {first_view, first_read, first_capture, first_observed} from "./first.ms"
import {second_view, second_read, second_capture, second_observed} from "./second.ms"
import panic from "@std/faults.ms"

test "accessor views and closures retain local implementation evidence":
    let item = Item(2)
    let first = first_view(item)
    let second = second_view(item)
    let captured_first = first_capture(item)
    let captured_second = second_capture(item)
    if first.value != 12 or second.value != 22:
        return panic("accessor view scope lost")
    if first_read(item) != 12 or second_read(item) != 22:
        return panic("generic accessor scope lost")
    if Read[Int](first).value != 12 or Read[Int](second).value != 22:
        return panic("repeated view changed scope")

    item.count = 4
    if first.value != 14 or second.value != 24:
        return panic("view accessor cached its value")
    if captured_first() != 14 or captured_second() != 24:
        return panic("captured accessor lost receiver or scope")

    let first_methods = first_observed(item)
    let second_methods = second_observed(item)
    if (
        invoke_observed(first_methods) != 18
        or invoke_observed(second_methods) != 28
        or invoke_observed(first_methods) != 18
    ):
        return panic("cached methods and accessor reads lost view evidence")
