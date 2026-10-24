# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:188 TestFormattingCheckAndPermissionPreservation
def value() -> Int:
    return sum(left: read(1), right: 2)
