// conform: tags=diagnostics
// conform: phase=check
fn zero() Int:
    return 0
export fn main() Int:
    return (1 /
        zero())
