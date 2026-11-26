// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:45 TestDiagnosticsStateCauseAndFix
fn f() Void {
	println("hi")
}
// expect-error: MS2001 5:5 unknown binding println; there is no println: use print(value), which writes any value and a newline; for write errors or bytes import stdout from "@std/io/io.ms" and call stdout().write("text\\n")
