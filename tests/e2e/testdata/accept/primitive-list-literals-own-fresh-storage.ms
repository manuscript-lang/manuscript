import {expect_equal, expect_true} from "@std/testing.ms"

fn fresh() -> List[Int]:
    return [1, 2, 3]

test "literals":
    let a = fresh()
    let b = fresh()
    a.append(value: 4)
    (a.length() == 4 and b.length() == 3) | try expect_true
    let floats = [1.5, 2.5]
    let flags = [true, false, true]
    let words = ["a", "b"]
    let empty = List[Int]()
    floats.length() | try expect_equal(expected: 2)
    flags.length() | try expect_equal(expected: 3)
    words.length() | try expect_equal(expected: 2)
    empty.length() | try expect_equal(expected: 0)
    floats.append(value: 3.5)
    words.append(value: "c")
    ((floats.at(index: 2) == some(3.5) and words.at(index: 2) == some("c"))) | try expect_true
    ([1, 2] == [1, 2] and not ([1, 2] == [2, 1])) | try expect_true
    let rows = [[1], [2, 3]]
    (rows.at(index: 1) == some([2, 3])) | try expect_true
