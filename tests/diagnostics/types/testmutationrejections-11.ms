// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:32 TestMutationRejections
fn f() Void {
	var value = 1
	value += 1.5
}
// expect-error: MS3001 6:11 operator operands require the same independently known type, found Int + Float; convert the Int with value.to_float(), or the Float with value.truncate_to_int() (returns Int?)
