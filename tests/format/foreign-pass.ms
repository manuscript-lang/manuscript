// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    pass
}
// expect-error: MS1000 5:5-5:9 'pass' is not a keyword; write 'void' for an empty block or match arm
// expect-fix: 5:5-5:9 "void"
// expect-format-exit: 1
