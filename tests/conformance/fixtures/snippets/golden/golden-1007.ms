// conform: tags=diagnostics
// conform: phase=check
fn f() {
    return
}
// expect-error: MS1000 3:8-3:9 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
