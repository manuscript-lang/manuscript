import {sorted_int, sorted_float, sorted_strings} from "@std/collections.ms"
import parse_float from "@std/numbers.ms"
import panic from "@std/faults.ms"

test "primitive sorting needs no comparator and returns fresh storage":
    let integers = [9223372036854775807, -9223372036854775808, 1, 0, 1]
    let ordered = sorted_int(integers)
    if ordered != [-9223372036854775808, 0, 1, 1, 9223372036854775807]: return panic(
        "exact integer sorting"
    )

    ordered.set(0, 3)
    if integers.first().unwrap() != 9223372036854775807: return panic(
        "sort copied no storage"
    )

    let sort: fn(values: List[Int]) -> List[Int] = sorted_int
    if sort([3, 1, 2]) != [1, 2, 3]: return panic("stored sorting function")
    if (
        sorted_strings(["🙂", "é", "e\u{301}", "a", "A"]) != [
            "A",
            "a",
            "e\u{301}",
            "é",
            "🙂"
        ]
    ): return panic("scalar lexical sorting")

    let empty: List[String] = []
    if not sorted_strings(empty).is_empty(): return panic("empty sorted list")

test "Float sorting places NaNs first and retains stable zero signs":
    let nan = parse_float("NaN").unwrap()
    let infinity = parse_float("Infinity").unwrap()
    let ordered = sorted_float([0.0, nan, 2.0, -0.0, -infinity, -2.0, infinity, nan])
    if not ordered[0].unwrap().is_nan() or not ordered[1].unwrap().is_nan(): return panic(
        "NaNs first"
    )
    if ordered.drop(2) != [-infinity, -2.0, 0.0, -0.0, 2.0, infinity]: return panic(
        "numeric Float order"
    )
    if (
        ordered[4].unwrap().to_string() != "0"
        or ordered[5].unwrap().to_string() != "-0"
    ): return panic("stable zero signs")
