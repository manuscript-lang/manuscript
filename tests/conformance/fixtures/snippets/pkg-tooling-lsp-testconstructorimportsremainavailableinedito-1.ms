# conform: tags=diagnostics,modules,stdlib-collections,stdlib-csv,strings,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/constructor_imports_test.go:9 TestConstructorImportsRemainAvailableInEditor
import SetBuilder from "@std/collections.ms"
import CsvOptions from "@std/csv.ms"
fn example() Unit:
    SetBuilder[String]()
    CsvOptions(delimiter: ",", line_ending: "\n")
