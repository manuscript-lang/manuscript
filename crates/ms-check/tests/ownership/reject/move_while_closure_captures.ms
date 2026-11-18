fn eat(move a: List[Int]) Int:
    return a.length()

fn main() Int:
    xs := [1]
    f := fn: xs.length()
    n := eat(xs)  // error: cannot move `xs` while `f` borrows it (closure capture, at 6:10); finish using `f` before this, or build `f` from a clone
    return n + f()
