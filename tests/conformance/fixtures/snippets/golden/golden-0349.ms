// conform: tags=diagnostics
// conform: phase=check
type Pair[T, U]:
    first: T
    second: U
type Config:
    value: Pair[Int?, String??]
