// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/native_result_test.go:35 TestNativeJSONCompileFailuresPreserveOutputs
export fn main() Int {
	return unknown_name
}
// expect-error: MS2001 5:12 unknown binding unknown_name; declare it with 'unknown_name := ...' before use, define 'fn unknown_name(...) T { ... }', or import it from a module
