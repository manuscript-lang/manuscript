# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# A non-escaping closure points at the captured value; it does not copy it.
# expect-mir-order: "fn @run" "slot Matrix" "store" "closure.new @<anonymous>"
# expect-mir-order: "fn @<anonymous>" "closure.cap 0" "load Matrix"
type Matrix:
    data: List[Int]

fn sum_with(m: Matrix, f: fn(Int) Int) Int:
    var total = 0
    for x in m.data:
        total += f(x)
    return total

fn run(m: Matrix) Int:
    return sum_with(m, fn x: x + m.data.length())

export fn main() Int:
    return run(Matrix(data: [1, 2, 3]))
