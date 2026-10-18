import {expect_true} from "@std/testing.ms"

fn fresh() List[Int]:
    return [1, 2, 3]

test "literals":
    let a = fresh()
    let b = fresh()
    a.append(value: 4)
    try expect_true((a.length() == 4 and b.length() == 3))
    let floats = [1.5, 2.5]
    let flags = [true, false, true]
    let words = ["a", "b"]
    let empty = List[Int]()
    try expect_true(
        (
            floats.length() == 2
            and flags.length() == 3
            and words.length() == 2
            and empty.length() == 0
        )
    )
    floats.append(value: 3.5)
    words.append(value: "c")
    try expect_true(
        (floats.at(index: 2) == some(3.5) and words.at(index: 2) == some("c"))
    )
    try expect_true(([1, 2] == [1, 2] and not ([1, 2] == [2, 1])))
    let rows = [[1], [2, 3]]
    try expect_true((rows.at(index: 1) == some([2, 3])))
