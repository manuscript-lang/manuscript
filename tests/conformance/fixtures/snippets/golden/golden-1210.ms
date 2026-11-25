// conform: tags=diagnostics
// conform: phase=check
fn answer(input Int) Void {
    if true {
        input := "text"
        inp|
    }
    return
}
// expect-error: MS1000 6:13-6:13 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
