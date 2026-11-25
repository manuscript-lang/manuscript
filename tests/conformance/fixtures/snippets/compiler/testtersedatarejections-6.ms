// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/terse_data_test.go:39 TestTerseDataRejections
fn f() Void {
	_value := {1: 2}
}
// expect-exit: 0
