from "@std/collections.ms" import range

def scalar(limit: Int) -> Int:
    var total = 0
    for index in range(0, limit):
        total += index
    return total

def add(left: Int, right: Int) -> Int: left + right

def calls(limit: Int) -> Int:
    var total = 0
    for index in range(0, limit):
        total = add(total, index)
    return total

def items(values: List[Int], limit: Int) -> Int:
    var total = 0
    for index in range(0, limit):
        total += values.get(index)
    return total
