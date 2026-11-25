// conform: tags=diagnostics
// conform: phase=check
fn wrong() {
  return
}
// expect-error: MS1000 3:12-3:13 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
