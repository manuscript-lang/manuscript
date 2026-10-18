import panic from "@std/faults.ms"
import DomainFailure from "./domain.ms"
import {first_error, first_result, first_propagated, first_generic, first_box} from "./first.ms"
import {second_error, relay} from "./second.ms"

test "Error boundaries retain selected local and generic implementations":
    let original = DomainFailure(7)
    let first = first_error(original)
    let second = second_error(original)
    if first.message() != "first 7" or second.message() != "second 7":
        return panic("Error boundary lost local dispatch")

    let others: List[Error] = [first_generic(original), first_box(original)]
    for cause in others:
        if cause.message() != "first 7":
            return panic("generic Error boundary lost dispatch evidence")
    original.code = 8

    for result in [first_result(original), first_propagated(original), relay(first)]:
        if result.is_ok(): return panic("expected domain failure")
        if result.err().message() != "first 8":
            return panic("Error Result changed identity or local dispatch")
