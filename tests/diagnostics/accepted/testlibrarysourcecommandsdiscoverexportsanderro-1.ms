// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/library_project_test.go:24 TestLibrarySourceCommandsDiscoverExportsAndErrors
export fn value() Int => return 3
// expect-exit: 0
