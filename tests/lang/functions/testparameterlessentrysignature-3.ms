// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=pkg/build/compiler_test.go:207 TestParameterlessEntrySignature
export fn main(value Int = 0) Int {
	return value
}
// expect-exit: 1
// expect-stderr: <DIR>/testparameterlessentrysignature-3.ms:4:8: type: entry must declare fn main; main takes no parameters, so remove them (read program arguments through the standard cli module)
// expect-stderr:    |
// expect-stderr:  4 | export fn main(value Int = 0) Int {
// expect-stderr:    |        ^
// expect-stderr: 1 error; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)
