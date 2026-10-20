# conform: tags=alternatives,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:240 TestContextualCallbackRecovery
type Choice:
    case Payload(value)
