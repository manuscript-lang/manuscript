// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
fn count[T](items List[T], extra Int) Int => extra

fn exercise() Int => count(1, 2)
// expect-error: MS3001 5:28 expected List[T], found Int; the argument must be a List[T], and the type variables are inferred from it
