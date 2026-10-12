import panic from "@std/faults.ms"

import List from "@std/collections.ms"

fn difference(values: List[Int]) -> Int:
    let [first, second] = values
    return first - second

test "list binding":
    if not (difference(values: [9, 4]) == 5):
        return panic(message: "check failed")

    let empty: List[Int] = []
    let {value: label} = Label(value: "ready")
    if not (label == "ready"):
        return panic(message: "check failed")

type Label:
    value: String
