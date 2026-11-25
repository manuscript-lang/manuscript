// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/library_project_test.go:34 TestLibrarySourceCommandsDiscoverExportsAndErrors
export fn other() Int => return "bad"
// expect-error: MS3001 4:33 expected Int, found String (in the return value)
