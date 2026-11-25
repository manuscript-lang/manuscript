// conform: tags=diagnostics
// conform: phase=check
import WriteStream from "@std/io/io.ms"
fn render(
    arguments List[String],
    output WriteStream
) Int {
    joined := arguments.jo|
    match output.write(data: "hello") {
    }
}
// expect-error: MS1000 8:28-8:28 a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found end of line; to continue a flow on the next line, end this line before '|' and start the next line with '|'
