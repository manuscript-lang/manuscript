from "@std/test.ms" import expect_equal
from "@std/collections.ms" import range

# A closure that does not outlive its maker reads what it captures in place; one that is
# returned or stored owns a copy and keeps the value it was made with.
type Matrix:
    data: List[Int]
    label: String

def total(m: Matrix, f: Callable[[Int], Int]) -> Int:
    var sum = 0
    for x in m.data:
        sum += f(x)
    return sum

def scaled(m: Matrix) -> Int:
    return total(m, lambda x: x + m.data.length())

def nested(m: Matrix, names: List[String]) -> Int:
    let outer = lambda (x: Int) -> Int:
        let inner = lambda (y: Int) -> Int:
            return y + m.data.length() + names.length()
        return inner(x)

    return total(m, outer)

def push(var out: List[Int], n: Int) -> Unit:
    out.append(n)

def each(f: Callable[[Int], Unit]) -> Unit:
    f(1)
    f(2)
    f(3)

def collect() -> List[Int]:
    var out: List[Int] = []
    each(lambda i: push(var out, i))
    return out

def make_reader() -> Callable[[], Int]:
    var tags = ["a"]
    tags.append("b")
    return lambda: tags.length()

test "non-escaping closure reads its capture":
    let m = Matrix(data: [1, 2, 3], label: "m")
    try expect_equal(scaled(m), 15)
    try expect_equal(nested(m, ["x", "y"]), 21)

test "closure made in a loop sees each iteration":
    var results: List[Int] = []

    for i in [1, 2, 3]:
        var names: List[String] = []
        for unused in range(0, i):
            names.append("n")

        let count = lambda: names.length()
        results.append(count())

    try expect_equal(results, [1, 2, 3])

test "closure passes a captured var on without copying":
    try expect_equal(collect(), [1, 2, 3])

test "escaping closure keeps its own value":
    let read = make_reader()
    try expect_equal(read(), 2)
