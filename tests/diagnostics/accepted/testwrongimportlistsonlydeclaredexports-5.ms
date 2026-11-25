// conform: tags=diagnostics,faults,formatter,modules,stdlib-faults,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:114 TestWrongImportListsOnlyDeclaredExports
import panic from "@std/core.ms"
// expect-exit: 0
