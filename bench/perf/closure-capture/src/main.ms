from "@std/collections.ms" import range

type Matrix:
    data: List[Int]

def apply(f: Callable[[Int], Int], n: Int) -> Int:
    var acc = 0
    for i in range(0, n):
        acc += f(i)
    return acc

export def main() -> Int:
    var data: List[Int] = []
    for i in range(0, 8000000):
        data.append(i)

    let m = Matrix(data: data)
    var total = 0
    for round in range(0, 50):
        total += apply(lambda i: m.data[(i + round) % 8000000], 10)
    return total % 100 + m.data.length() % 7
