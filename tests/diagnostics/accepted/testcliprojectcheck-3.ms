// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/project_check_test.go:58 TestCLIProjectCheck
fn number() Int => return 1
// expect-exit: 0
