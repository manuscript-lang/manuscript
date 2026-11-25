// conform: tags=diagnostics
// conform: phase=check
interface Read {
    fn read()
}
// expect-error: MS1000 4:14-4:14 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
