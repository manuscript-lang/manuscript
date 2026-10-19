# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=internal/cli/cli_test.go:187 TestFormattingCheckAndPermissionPreservation
fn value() Int:
    if true: return 3
    return 0
