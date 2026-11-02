# conform: tags=formatter,modules,mutation,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:11 TestSemanticLintUsesReadsAndControlFlow
import ListEntry from "@std/collections/collections.ms"

fn answer() Int:
    let _unused = 1
    var _written = 2
    _written = 3
    return 0
    return 1
