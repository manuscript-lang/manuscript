type Box[A: Hashable, B: Hashable = A]:
    x: A
    y: B

type Keyed[A: Hashable, B = Map[A, Int]]:
    x: A
    y: B

type Chain[A: Equal, B: Equal = A, C: Equal = B]:
    x: A
    y: B
    z: C

enum Choice[A: Clonable, B: Clonable = A]:
    first(value: A)
    second(other: B)

interface Holder[A: Hashable, B: Hashable = A]:
    fn first() A
    fn second() B

fn pair[A: Hashable, B: Hashable = A](a: A, b: B) Int:
    return 0
