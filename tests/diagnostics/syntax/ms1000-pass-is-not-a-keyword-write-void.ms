// conform: tags=diagnostics
// conform: phase=check
fn f(a Int) Void {
    if a == 1 {
        pass
    }
}
// expect-error: MS1000 5:9-5:13 'pass' is not a keyword; write 'void' for an empty block or match arm
// expect-fix: 5:9-5:13 "void"
