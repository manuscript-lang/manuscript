# conform: tags=alternatives,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/positional_arguments_test.go:57 TestConstructorIdentifierRenameDoesNotAddLabels
type Pair:
    case Values(first: Int, second: Int)
