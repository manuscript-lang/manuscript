// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
type P:
    n Int = 1

fn label(p P) String:
    return "x"

fn main() Void:
    p := P()
    print(p.label())
