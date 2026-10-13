import {
    first_mapped,
    first_bound_map,
    first_generic_map,
    first_lookup,
    first_failure,
    first_queries,
    first_converted,
    first_folded
} from "./first.ms"
import {
    second_mapped,
    second_failure,
    second_queries,
    second_converted,
    second_folded
} from "./second.ms"
import {Key, Cause} from "./domain.ms"
import panic from "@std/faults.ms"
import Set from "@std/collections.ms"

test "mapped output keeps lexical Hashable and Equal evidence":
    let by_id = first_mapped()
    let by_label = second_mapped()
    if by_id.length() != 1 or by_label.length() != 2:
        return panic("generic result scope was replaced by input scope")
    if by_id.values().at(0).unwrap().label != "1": return panic(
        "first mapped payload lost"
    )

    let bound = first_bound_map()
    let mapped = bound(
        fn(n): Key(
            0,
            n.toString()
        )
    )
    if mapped.length() != 1: return panic("bound map lost defining module")

    let input = Set[Int]().with_value(1).with_value(2)
    if first_generic_map(input).length() != 1:
        return panic("mapped generic output used receiver's module")
    if first_lookup() != "found": return panic("generic get_or lost key scope")

test "Result composition retains concrete Error and its local implementation":
    let cause = Cause(1)
    let one = first_failure(cause)
    let two = second_failure(cause)
    if (
        one.unwrap_error().message() != "first 1"
        or two.unwrap_error().message() != "second 1"
    ):
        return panic("Result error scope changed")

    cause.count = 2
    if cause.count != 2 or two.unwrap_error().message() != "second 2":
        return panic("Result copied concrete Error")

test "conversions and queries retain scoped generic evidence and Error identity":
    if not (first_queries()) or not (second_queries()):
        return panic("query callback lost generic equality evidence")

    let cause = Cause(1)
    let one = first_converted(cause)
    let two = second_converted(cause)
    if (
        one.unwrap_error().message() != "first 1"
        or two.unwrap_error().message() != "second 1"
    ):
        return panic("conversion replaced Error implementation")

    cause.count = 3
    if (
        one.unwrap_error().message() != "first 3"
        or two.unwrap_error().message() != "second 3"
    ):
        return panic("conversion copied concrete Error")
    if not (one.to_optional().is_none()): return panic("error converted to success")

test "generic folds preserve scoped interface accumulators":
    let cause = Cause(4)
    let one = first_folded(cause)
    let two = second_folded(cause)
    if one.message() != "first 4" or two.message() != "second 4":
        return panic("fold replaced interface accumulator evidence")

    cause.count = 5
    if one.message() != "first 5" or two.message() != "second 5":
        return panic("fold copied interface accumulator")
