// conform: tags=diagnostics
// conform: phase=check
import WriteStream from "@std/io/io.ms"
fn render(
    arguments: List[String],
    output: WriteStream
) Int:
    joined := arguments.jo|
    match output.write(data: "hello"):
