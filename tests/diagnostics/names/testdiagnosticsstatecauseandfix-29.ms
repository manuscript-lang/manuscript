// conform: tags=diagnostics,formatter,modules,stdlib-faults,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:48 TestDiagnosticsStateCauseAndFix
import nope from "@std/core.ms"

fn f() Void {
	return
}
// expect-error: MS2002 4:8-4:12 module does not export nope; @std/core.ms exports: Clonable, Closeable, Comparable, Data, Equal, Error, Hashable, Iterator, Optional, Result, Stringable, Writable, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/core.ms"'
