// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
fn count[T](items List[T], extra Int) Int => extra

fn exercise() Int => count(1, 2)
