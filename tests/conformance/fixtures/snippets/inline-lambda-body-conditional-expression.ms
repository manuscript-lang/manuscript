# conform: tags=closures,control-flow,tier-core
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
fn f(x: Int) Int:
    let y = if x > 1: x else: 0
    return y
fn g(x: Int) Int:
    return if x > 1: x else: 0
fn h(xs: List[Int]) List[Int]:
    return xs.map(fn x: if x > 1: x else: 0)
export fn main() Int:
    return f(2) + g(3) + h([1, 5])[1]
