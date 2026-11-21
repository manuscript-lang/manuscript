import id, first_of from "./lib.ms"

fn main() Int:
    a := id(4)
    b := id(2.5)
    c := first_of(7, 8)
    d := first_of(1.0, 2.0)
    if b > d:
        return a
    return c
