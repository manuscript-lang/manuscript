// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
fn f() Void {
    try {
        g()
    }
}
// expect-error: MS1000 5:5-5:8 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
// expect-format-exit: 1
