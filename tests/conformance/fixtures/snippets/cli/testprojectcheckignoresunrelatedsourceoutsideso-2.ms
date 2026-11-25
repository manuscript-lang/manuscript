// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/project_check_test.go:105 TestProjectCheckIgnoresUnrelatedSourceOutsideSourceDirectory
fn value() Int => return 1
// expect-exit: 0
