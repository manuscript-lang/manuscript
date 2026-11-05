type Item:
    value: Int

type Pair[A, B = A]:
    first: A
    second: B

type Root:
    value: Pair[Pair[Pair[Pair[Pair[Pair[Pair[Pair[Pair[Pair[Pair[Pair[Item]]]]]]]]]]]]
