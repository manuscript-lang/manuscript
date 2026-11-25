// conform: tags=diagnostics
// conform: phase=check
fn value(i Int) Int => i
fn fail() Int {
    return 1 / 0
}
export fn main() Int {
    data := 
}
// expect-error: MS1000 8:13-8:13 expected an expression, found end of line; write a value, name, call, or literal here
