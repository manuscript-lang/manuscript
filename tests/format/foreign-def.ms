// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
def f() -> Void {
    return
}
// expect-error: MS1000 4:1-4:4 'def' is not a Manuscript declaration keyword; declare a function as 'fn name(a Int) Int { ... }' with the result type after the parameters
// expect-fix: 4:1-4:4 "fn"
// expect-format-exit: 1
