// conform: tags=diagnostics
// conform: phase=check
interface Named:
    fn name() String
fn f[T: Named = Int]() Unit: unit
