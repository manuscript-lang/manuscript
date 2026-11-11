// conform: tags=diagnostics
// conform: phase=check
interface Named:
    fn name() String
fn text(value: Named) String:
    return value.|
