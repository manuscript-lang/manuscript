// conform: tags=diagnostics
// conform: phase=check
fn use(entries Map[String, Int]) Void {
    entries.ad|
}
// expect-error: MS1000 4:16-4:16 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
