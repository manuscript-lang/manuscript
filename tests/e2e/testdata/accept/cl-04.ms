import panic from "@std/faults.ms"

fn difference(values: List[Int]) Int:
    let [first, second] = values
    return first - second

test "list binding":
    if not (difference([9, 4]) == 5):
        return panic("check failed")

    let {value: label} = Label("ready")
    if not (label == "ready"):
        return panic("check failed")

type Label:
    value: String
