// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/project_check_test.go:50 TestProjectCheckDiscoveryAndReporting
export fn value() Int => return 0
// expect-exit: 0
