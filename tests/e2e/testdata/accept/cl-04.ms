import List from "@std/collections.ms"

fn difference(values: List[Int]) -> Int:
    let [first, second] = values
    return first - second

test "list binding":
    assert difference(values: [9, 4]) == 5
    let empty: List[Int] = []
    let {value: label} = Label(value: "ready")
    assert label == "ready"

type Label:
    value: String
