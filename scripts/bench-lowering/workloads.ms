fn scalar(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = total + index % 7
        index = index + 1
    return total

fn add(left: Int, right: Int) -> Int: left + right
fn identity(value: Int) -> Int: value
fn generic[T](value: T) -> T: value

fn calls(limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = add(total, index % 7)
        index = index + 1
    return total

fn items(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = total + values.at(index % values.length()).unwrap()
        index = index + 1
    return total

fn capture(value: Int) -> Int:
    let callback = fn() -> Int: value
    return callback() + 1
fn stored(value: Int) -> Int:
    let values = [value]
    return values.at(0).unwrap() + 1
fn forwarded(value: Int) -> Int: identity(value)
fn copied(value: Int) -> Int:
    let copy = value
    return generic(copy)

fn life(side: Int, generations: Int) -> Int:
    var cells: List[Int] = []
    var index = 0
    while index < side * side:
        if index % 7 == 0: cells.append(1)
        else: cells.append(0)
        index = index + 1
    var generation = 0
    while generation < generations:
        let next: List[Int] = []
        index = 0
        while index < side * side:
            let row = index / side
            let col = index % side
            let north = (row + side - 1) % side
            let south = (row + 1) % side
            let west = (col + side - 1) % side
            let east = (col + 1) % side
            let neighbours = cells.at(north * side + west).unwrap() + cells.at(north * side + col).unwrap() + cells.at(north * side + east).unwrap() + cells.at(row * side + west).unwrap() + cells.at(row * side + east).unwrap() + cells.at(south * side + west).unwrap() + cells.at(south * side + col).unwrap() + cells.at(south * side + east).unwrap()
            if neighbours == 3 or (neighbours == 2 and cells.at(index).unwrap() == 1): next.append(1)
            else: next.append(0)
            index = index + 1
        cells = next
        generation = generation + 1
    var alive = 0
    index = 0
    while index < side * side:
        alive = alive + cells.at(index).unwrap()
        index = index + 1
    return alive

fn matched(values: List[Int], limit: Int) -> Int:
    var total = 0
    var index = 0
    while index < limit:
        total = total + (match values.at(index % values.length()):
            some(value): value
            none: 0
        )
        index = index + 1
    return total

fn ranged(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total = total + value
    return total

fn compare(left: Int, right: Int) -> Int: left - right
fn sort_values(values: List[Int]) -> Int:
    let sorted = values.sorted(compare)
    return sorted.at(0).unwrap()
fn sort_captured(values: List[Int]) -> Int:
    let bias = 1000
    let compare = fn(left: Int, right: Int) -> Int: (left + bias) - (right + bias)
    let sorted = values.sorted(compare)
    return sorted.at(0).unwrap()
