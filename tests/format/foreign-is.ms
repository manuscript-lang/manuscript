// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f(a Int) Void {
    b := a is 1
}
// expect-error: MS1000 5:12-5:14 expected end of statement, found name 'is'; there is no 'is' operator: write '==' to compare values, or 'match value { ... }' to test which alternative a value is
// expect-format-exit: 1
