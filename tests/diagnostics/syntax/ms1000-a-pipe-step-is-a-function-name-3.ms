// conform: tags=diagnostics
// conform: phase=check
fn answer() Int {
    before := 1
    be|
    behind := 2
    return before
}
// expect-error: MS1000 5:8-5:8 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
