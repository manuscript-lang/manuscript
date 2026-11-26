// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    a := new Point()
}
// expect-error: MS1000 5:14-5:19 expected end of statement, found name 'Point'; there is no 'new': construct a value by calling the type, Name(field: value)
// expect-format-exit: 1
