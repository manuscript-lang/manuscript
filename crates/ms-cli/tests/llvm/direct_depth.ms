fn alternate(n: Float) Float:
    if n < 1.0:
        return 0.0
    return n - alternate(n - 1.0)

fn main() Int:
    print(alternate(10.0))
    print(alternate(3000000.0))
    return 0
