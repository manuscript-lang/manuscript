# conform: tags=diagnostics,modules,mutation,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:11 TestSemanticLintUsesReadsAndControlFlow
import ListEntry from "@std/collections/collections.ms"

fn answer() Int:
    let _unused = 1
    var _written = 2
    _written = 3
    return 0
    return 1
