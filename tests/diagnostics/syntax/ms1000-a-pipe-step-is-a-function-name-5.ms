// conform: tags=diagnostics
// conform: phase=check
fn size(text String) Int {
    return text.byte_|
}
// expect-error: MS1000 4:23-4:23 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
