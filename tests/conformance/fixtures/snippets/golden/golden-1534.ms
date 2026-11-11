// conform: tags=diagnostics
// conform: phase=check
type Grow[T]:
    next: fn() Grow[List[T]]
export fn main() Int: return 0
