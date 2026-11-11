// conform: tags=diagnostics
// conform: phase=check
type Pair[A, B = A]:
    first: A
    second: B
fn use() Pair[Int]: Pair[Int](1, 2)
