// conform: tags=diagnostics
// conform: phase=check
type Trio[A, B, C = A]:
    first: A
fn use(t: Trio[Int]) Unit: unit
