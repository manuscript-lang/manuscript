// conform: tags=diagnostics
// conform: phase=check
type Grow[T]:
    next: Bridge
type Bridge:
    next: Grow[Int]
