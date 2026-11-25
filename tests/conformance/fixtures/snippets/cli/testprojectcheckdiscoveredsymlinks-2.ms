// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/project_check_test.go:143 TestProjectCheckDiscoveredSymlinks
fn value() Int => return 0
// expect-exit: 0
