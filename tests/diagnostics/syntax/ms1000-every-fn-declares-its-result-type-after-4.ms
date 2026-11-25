// conform: tags=diagnostics
// conform: phase=check
fn bad() {
  return
}
// expect-error: MS1000 3:10-3:11 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
