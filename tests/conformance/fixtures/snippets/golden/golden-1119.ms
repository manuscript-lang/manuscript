// conform: tags=diagnostics
// conform: phase=check
fn double(n: Int) Int: n * 2

fn run(n: Int) Int:
    a := n|double|double
    b := n
        |double   // first
        // second
        |double
    return a+b
