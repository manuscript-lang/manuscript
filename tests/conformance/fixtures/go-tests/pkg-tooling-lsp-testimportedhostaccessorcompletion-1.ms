# conform: tags=modules,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:219 TestImportedHostAccessorCompletion
import stdout from "@std/io.ms"
export fn main() Int:
    stdout().wr|
    return 0
