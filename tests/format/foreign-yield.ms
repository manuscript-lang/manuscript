// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    yield 1
}
// expect-error: MS1000 5:5-5:10 'yield' is not a keyword; there are no generators, so build a list and return it
// expect-format-exit: 1
