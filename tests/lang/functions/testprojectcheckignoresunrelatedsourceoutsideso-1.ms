// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=internal/cli/project_check_test.go:104 TestProjectCheckIgnoresUnrelatedSourceOutsideSourceDirectory
export fn main() Int => return 0
// expect-exit: 0
