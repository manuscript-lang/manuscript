// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn main() {
    print(1)
}
// expect-error: MS1000 4:11-4:12 every fn declares its result type after the parameter list, e.g. fn f() Void { ... } (Void when it returns nothing)
// expect-format-exit: 1
