fn main() Int:
    var total = 0
    add := fn(x: Int) Void:
        total += x
    add(1)
    return total
