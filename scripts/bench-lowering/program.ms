import List from "@std/collections.ms"

fn scalar(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = total + index
        index = index + 1
    return total

fn add(left: Int, right: Int) -> Int: left + right

fn calls(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = add(left: total, right: index)
        index = index + 1
    return total

fn items(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = total + values.at(index).unwrap()
        index = index + 1
    return total
