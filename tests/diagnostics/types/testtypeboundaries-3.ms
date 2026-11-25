// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:655 TestTypeBoundaries
fn invalid(value fn() Int) Bool {
	return value == value
}
// expect-error: MS3000 5:18 equality requires Equal operands; fn() Int has no equality, so give it 'fn fn() Int.equals(other: fn() Int) Bool' or compare fields
