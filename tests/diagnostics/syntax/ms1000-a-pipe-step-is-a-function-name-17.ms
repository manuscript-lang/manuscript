// conform: tags=diagnostics
// conform: phase=check
fn combine(first Int = 3, second Int = fir|) Int {
    return second
}
// expect-error: MS1000 3:44-3:45 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found ')'
