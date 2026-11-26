// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() -> Int {
    return 0
}
// expect-error: MS1000 4:8-4:10 result types follow the parameter list without an arrow; remove '->', e.g. fn f() Void { ... }
// expect-fix: 4:8-4:10 ""
// expect-format-exit: 1
