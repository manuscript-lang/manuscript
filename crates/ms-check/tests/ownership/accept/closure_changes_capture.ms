fn main() Int:
    var total = 0
    let add = fn(x: Int) Unit:
        total += x
    add(1)
    return total
