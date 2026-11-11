fn Int.read() Int:
    return 1

fn Missing.read() Int:
    return 2

type Box[T]:
    value: T

fn T.read() Int:
    return 3
