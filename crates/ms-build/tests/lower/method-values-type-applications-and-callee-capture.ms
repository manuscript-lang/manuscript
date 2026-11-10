// Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
// expect-mir: "closure.new"

import stdout from "@std/io/io.ms"

fn identity[T](value: T) T: value

fn run(f: fn(Int) Int) Int: f(1)

fn main() Unit:
    items := [4, 5]
    count := items.count
    lookup := items.get
    same := identity[Int]
    var selected = identity[Int]
    if present(0).is_some():
        selected = fn(value: Int): value + 1

    n := selected(3)
    _r := stdout().write("{lookup(1)} {n} {run(same)} {count(fn(x: Int): x > 4)}\n")

fn present[T](value: T) T?:
    return value
