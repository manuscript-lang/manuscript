// conform: tags=diagnostics
// conform: phase=check
fn subtract(amount Int, deduction Int = 1) Int {
    return amount - deduction
}
fn call() Int {
    return sub|
}
// expect-error: MS1000 7:16-7:16 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
