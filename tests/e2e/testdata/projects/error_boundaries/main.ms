import panic from "@std/faults.ms"
import DomainFailure from "./domain.ms"
import {first_error, first_result, first_propagated, first_generic, first_box} from "./first.ms"
import {second_error, relay} from "./second.ms"

test "Error boundaries retain selected local and generic implementations":
    let original = DomainFailure(7)
    let first = first_error(original)
    let second = second_error(original)
    if first.message() != "first 7" or second.message() != "second 7":
        return panic(message: "Error boundary lost local dispatch")

    let others: List[Error] = [first_generic(original), first_box(original)]
    for cause in others:
        if cause.message() != "first 7":
            return panic(message: "generic Error boundary lost dispatch evidence")
    original.code = 8

    for result in [first_result(original), first_propagated(original), relay(first)]:
        match result:
        ok(_):
            return panic(message: "expected domain failure")
        error(cause):
            if cause.message() != "first 8":
                return panic(message: "Error Result changed identity or local dispatch")
