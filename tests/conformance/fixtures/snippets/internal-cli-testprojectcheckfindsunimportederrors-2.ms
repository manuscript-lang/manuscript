# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=internal/cli/project_check_test.go:17 TestProjectCheckFindsUnimportedErrors
fn number() Int:
    return "wrong"

fn text() String:
    return 1
