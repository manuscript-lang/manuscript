// conform: tags=diagnostics
// conform: phase=check
fn prepare() fn() Int {
    invalid := 1 / 0
    return fn() Int => 1
}
export fn main()
// expect-error: MS1000 7:17-7:17 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
