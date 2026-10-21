fn main() Unit:
    var total = 0
    let add = fn(x: Int) Unit:
        total += x
    add(1)
    print(total)
