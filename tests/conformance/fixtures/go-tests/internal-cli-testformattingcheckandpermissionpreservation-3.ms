# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=internal/cli/cli_test.go:187 TestFormattingCheckAndPermissionPreservation
fn value() Int:
    if true: return 3
    return 0
