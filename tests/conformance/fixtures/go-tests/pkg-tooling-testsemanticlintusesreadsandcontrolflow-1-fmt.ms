# conform: tags=formatter,modules,mutation,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:11 TestSemanticLintUsesReadsAndControlFlow
import ListBuilder from "@std/collections.ms"
fn answer() Int:
    let unused = 1
    var written = 2
    written = 3
    return 0
    return 1
