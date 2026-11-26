// conform: tags=diagnostics
// conform: phase=check
fn work(a Int) Int {
    b := a + 1
    c := = 3
    return b
}

export fn main() Int {
    return work(2)
}
// expect-error: MS1000 5:10-5:11 expected an expression, found '='; write a value, name, call, or literal here
