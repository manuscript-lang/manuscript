// conform: tags=diagnostics
// conform: phase=check
fn run(n Int) Int {
    a := n | .size() | try .m() | .k
    return a
}
// expect-error: MS1000 4:24-4:27 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
