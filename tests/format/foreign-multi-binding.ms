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
// expect-error: MS1000 9:5-9:6 a statement cannot start with a comma-separated list of names: write one binding per line ('a := f()'), or destructure one value with '[a, b] := value'
// expect-format-exit: 1
