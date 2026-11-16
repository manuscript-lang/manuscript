fn a(x: Int) Int:
    if x <= 0: return 1
    return a(x - 1) + 2

fn b(x: Int) Int:
    if x <= 0: return 0
    return b(x - 1) + x % 3

fn c(x: Int) Int:
    if x <= 0: return 3
    return c(x - 1) + a(x) + b(x)

export fn main() Int:
    return c(10) % 100
