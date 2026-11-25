// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/library_project_test.go:25 TestLibrarySourceCommandsDiscoverExportsAndErrors
export fn other() Int => return 4
// expect-exit: 0
