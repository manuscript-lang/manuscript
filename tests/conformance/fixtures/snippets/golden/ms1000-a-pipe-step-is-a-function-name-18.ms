// conform: tags=diagnostics
// conform: phase=check
type Options {
    first Int = 3
    second Int = fir|
    later Int = 7
}
// expect-error: MS1000 5:22-5:22 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
