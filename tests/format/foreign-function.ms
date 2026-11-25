// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
function f() {
    return
}
// expect-error: MS1000 4:1-4:9 'function' is not a Manuscript declaration keyword; declare a function as 'fn name(a Int) Int { ... }' with the result type after the parameters
// expect-fix: 4:1-4:9 "fn"
// expect-format-exit: 1
