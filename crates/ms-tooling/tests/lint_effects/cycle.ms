fn a(n: Int) Int:
    if n == 0:
        return 0
    return b(n - 1)

fn b(n: Int) Int:
    print(n)
    return a(n)

export fn main() Int:
    return a(3)
