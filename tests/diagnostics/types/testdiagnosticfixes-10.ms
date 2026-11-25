// conform: tags=diagnostics,faults,formatter,modules,stdlib-faults,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:30 TestDiagnosticFixes
import panic from "@std/core.ms"

fn f() Int {
	panic = 2
	return 0
}
// expect-error: MS3000 7:5 cannot assign to imported function panic; assignment targets are 'var' bindings and type fields
