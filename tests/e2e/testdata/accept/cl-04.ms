import {expect_equal} from "@std/testing.ms"

fn difference(values: List[Int]) Int:
    let [first, second] = values
    return first - second

test "list binding":
    try expect_equal(difference([9, 4]), 5)
    let {value: label} = Label("ready")
    try expect_equal(label, "ready")

type Label:
    value: String
