# conform: tags=diagnostics,modules,mutation,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:11 TestSemanticLintUsesReadsAndControlFlow
from "@std/collections.ms" import ListBuilder

def answer() -> Int:
    let unused = 1
    var written = 2
    written = 3
    return 0
    return 1
