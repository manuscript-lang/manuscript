# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/positional_arguments_test.go:27 TestPositionalIdentifierRenameDoesNotAddLabels
def subtract(amount: Int, deduction: Int) -> Int: amount - deduction

def run() -> Int:
    let number = 10
    return subtract(number, 3)
