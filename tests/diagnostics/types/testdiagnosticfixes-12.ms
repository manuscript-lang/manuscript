// conform: tags=control-flow,diagnostics,formatter,interfaces,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:32 TestDiagnosticFixes
interface I {
	fn n() Int
}

type Pair[A, B] {
	a A
	b B
}

fn Pair[A, A].n() Int {
	return 1
}

export fn main() Int {
	return I(value: Pair[Int, String](a: 1, b: "x")).n()
}
// expect-error: MS3000 18:12 I is an interface and cannot be constructed; a type whose methods match I passes wherever I is expected, so pass the value directly
