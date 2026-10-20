# conform: tags=lists,match,modules,parser,stdlib-io,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:198 TestCompletionWithMultilineParameters
import WriteStream from "@std/io.ms"
fn render(
    arguments: List[String],
    output: WriteStream
) Int:
    let joined = arguments.jo|
    match output.write(data: "hello"):
