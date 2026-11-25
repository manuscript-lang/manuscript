// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    return ()
}
// expect-error: MS1000 5:12-5:13 '()' is not a value; the Void value is written 'void'
// expect-format-exit: 1
