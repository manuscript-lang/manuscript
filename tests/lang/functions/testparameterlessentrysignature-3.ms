// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=pkg/build/compiler_test.go:207 TestParameterlessEntrySignature
export fn main(value Int = 0) Int {
	return value
}
