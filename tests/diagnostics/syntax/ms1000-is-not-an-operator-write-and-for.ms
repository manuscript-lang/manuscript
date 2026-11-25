// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    if true && false {
        return 1
    }
    return 0
}
// expect-error: MS1000 4:13-4:15 '&&' is not an operator; write 'and' for logical and
// expect-fix: 4:13-4:15 "and"
