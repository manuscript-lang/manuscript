// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:29 TestMutationRejections
fn f() Void {
	value := 1
	value += 1
}
// expect-error: MS3060 6:5 cannot assign immutable binding value; declare it with 'var value = ...' instead of 'value := ...'
// expect-fix: 5:5-5:13 "var value ="
