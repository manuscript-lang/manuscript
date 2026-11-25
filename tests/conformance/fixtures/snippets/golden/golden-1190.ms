// conform: tags=diagnostics
// conform: phase=check
fn answer() Int {
    if true {
        secret := 1
    }
    sec|
    return 0
}
// expect-error: MS1000 7:9-7:9 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
