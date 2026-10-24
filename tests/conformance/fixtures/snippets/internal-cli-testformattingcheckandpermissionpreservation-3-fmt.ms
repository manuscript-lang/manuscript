# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:187 TestFormattingCheckAndPermissionPreservation
def value() -> Int:
    if True: return 3

    return 0
