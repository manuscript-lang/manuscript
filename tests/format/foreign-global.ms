// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    global count
}
// expect-error: MS1000 5:5-5:11 'global' is not a keyword; a fn sees module constants directly, and mutable state lives in a 'var' or a field passed explicitly
// expect-format-exit: 1
