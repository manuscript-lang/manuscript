// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:30 TestMutationRejections
fn f(value Int) Void {
	value -= 1
}
// expect-error: MS3060 5:5 cannot assign immutable binding value; declare it with 'var value = ...' instead of 'value := ...'
