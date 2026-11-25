// conform: tags=closures,diagnostics,formatter,modules,stdlib-csv,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/constructor_imports_test.go:35 TestShadowedConstructorNameDoesNotRetainImport
import CsvOptions from "@std/data/csv.ms"

fn example(CsvOptions fn() Void) Void {
	CsvOptions()
}
// expect-exit: 0
