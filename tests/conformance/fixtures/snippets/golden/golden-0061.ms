// conform: tags=diagnostics
// conform: phase=check
fn main() {
    value := 42
    print(value)
}
// expect-error: MS1000 3:11-3:12 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
