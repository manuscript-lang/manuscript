// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    a := 1 |
        g
    return a
}
// expect-error: MS1000 4:13-4:13 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
