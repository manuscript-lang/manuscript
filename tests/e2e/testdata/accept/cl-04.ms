import {expect_equal} from "@std/testing.ms"

fn difference(values: List[Int]) -> Int:
    let [first, second] = values
    return first - second

test "list binding":
    difference(values: [9, 4]) | try expect_equal(expected: 5)
    let empty: List[Int] = []
    let {value: label} = Label("ready")
    label | try expect_equal(expected: "ready")

type Label:
    value: String
