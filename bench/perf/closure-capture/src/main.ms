type Matrix:
    data: List[Int]

fn apply(f: fn(Int) Int, n: Int) Int:
    var acc = 0
    for i in 0..n:
        acc += f(i)
    return acc

export fn main() Int:
    var data: List[Int] = []
    for i in 0..8000000:
        data.append(i)

    let m = Matrix(data: data)
    var total = 0
    for round in 0..50:
        total += apply(fn i: m.data[(i + round) % 8000000], 10)
    return total % 100 + m.data.length() % 7
