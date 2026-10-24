# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:117 TestListLiteralNeedsNoImport
def answer() -> Int:
    let items = [1, 2, 3]
    return items.length()
