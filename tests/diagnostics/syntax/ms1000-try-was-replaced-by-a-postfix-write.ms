// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    var x Int = 1
    x += try 3
    return x
}
// expect-error: MS1000 5:10-5:13 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
