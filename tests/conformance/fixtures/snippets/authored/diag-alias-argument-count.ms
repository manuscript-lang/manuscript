// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-aliases
type Bad[T] = List[T]

fn f(x: Bad) Int:
    return 0
