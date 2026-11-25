// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/project_check_test.go:73 TestProjectCheckDiscoveryAndReporting
fn broken() Int => return "bad"
// expect-error: MS3001 4:27 expected Int, found String (in the return value)
