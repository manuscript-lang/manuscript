// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Int {
    g := lambda x: x
    return 0
}
// expect-error: MS1000 5:17-5:18 expected end of statement, found name 'x'; there is no 'lambda': write an anonymous function as 'x => x + 1'
// expect-format-exit: 1
