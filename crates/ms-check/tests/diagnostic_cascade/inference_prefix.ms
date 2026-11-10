type Pair[A, B]:
    first: A
    second: B

fn probe[T](_pair: Pair[T, Int], _later: T) Int: 0

fn exercise() Int:
    return probe(Pair(1, "x"), "later")
