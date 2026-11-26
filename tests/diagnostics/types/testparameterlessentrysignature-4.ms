// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:208 TestParameterlessEntrySignature
export fn main[T]() Int {
	return 0
}
// expect-error: MS3000 4:8 entry must declare fn main; main cannot be generic, so remove its type parameters
