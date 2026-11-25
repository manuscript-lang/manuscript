// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Int {
    return 1
}

fn main() Void {
    a, b := f()
    print(a)
}
