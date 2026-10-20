# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=internal/cli/project_check_test.go:17 TestProjectCheckFindsUnimportedErrors
fn number() Int:
    return "wrong"

fn text() String:
    return 1
