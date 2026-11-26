// conform: tags=diagnostics
// conform: phase=check
fn answer(
    input Int,
) Int {
    return inp|
}
fn broken(
// expect-error: MS1000 6:16-6:16 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
// expect-error: MS1000 11:1 unterminated delimiter '(' opened at line 8:10; add the matching ')' before the end of the file
