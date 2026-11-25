// conform: tags=diagnostics,formatter,modules,stdlib-collections,stdlib-csv,strings,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/constructor_imports_test.go:9 TestConstructorImportsRemainAvailableInEditor
import (
	Partition from "@std/collections/collections.ms",
	CsvOptions from "@std/data/csv.ms",
)

fn example() Void {
	Set[String]()
	CsvOptions(delimiter: ",", line_ending: "\n")
}
// expect-exit: 0
