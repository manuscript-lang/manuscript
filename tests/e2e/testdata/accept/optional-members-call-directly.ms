import {expect_true} from "@std/testing.ms"

fn fallback() -> Int: 9

test "optional members":
    let present = some(3)
    let absent: Optional[Int] = none
    (present.is_some() and not present.is_none()) | try expect_true
    (absent.is_none() and not absent.is_some()) | try expect_true
    (present.unwrap_or(fallback: 7) == 3) | try expect_true
    (absent.unwrap_or(fallback: 7) == 7) | try expect_true
    (absent.unwrap_or_else(create: fn() -> Int: fallback()) == 9) | try expect_true
    (present.map(fn(value: Int) -> Int: value + 1).unwrap() == 4) | try expect_true
    let items = List[Int]()
    (items.at(index: 0).is_none()) | try expect_true
    items.append(value: 5)
    try expect_true(
        (
            items.at(index: 0).is_some()
            and items.first().unwrap_or(fallback: 0) == 5
        )
    )
