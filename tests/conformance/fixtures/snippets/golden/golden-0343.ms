// conform: tags=diagnostics
// conform: phase=check
type Phantom[T]:
    value: Int
type Grow[T]:
    value: Phantom[Grow[List[T]]]
