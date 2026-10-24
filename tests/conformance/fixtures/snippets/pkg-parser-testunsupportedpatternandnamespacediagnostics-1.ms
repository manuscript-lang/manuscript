# conform: tags=match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/diagnostics_test.go:47 TestUnsupportedPatternAndNamespaceDiagnostics
def f(command: String) -> Int:
    match command:
        case "réport": return 1

    return 0
