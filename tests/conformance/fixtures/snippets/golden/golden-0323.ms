// conform: tags=diagnostics
// conform: phase=check
interface A:
    fn a() Int
interface B:
    fn b() Int
fn f(value: A) B: value
