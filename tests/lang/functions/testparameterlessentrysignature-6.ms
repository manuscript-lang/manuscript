// conform: tags=functions,tier-core
// conform: phase=run
// conform: origin=pkg/build/compiler_test.go:210 TestParameterlessEntrySignature
export fn main() Float {
	return 0.0
}
// expect-exit: 1
// expect-stderr: <DIR>/testparameterlessentrysignature-6.ms:4:8: type: entry must declare fn main; main returns Float, so return Void, Void! (an error prints and exits 1), Int?!, or an Int exit status
// expect-stderr:    |
// expect-stderr:  4 | export fn main() Float {
// expect-stderr:    |        ^
// expect-stderr: 1 error; fix them and re-run
