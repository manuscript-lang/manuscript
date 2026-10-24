# conform: tags=diagnostics,modules,stdlib-collections,stdlib-csv,strings,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/constructor_imports_test.go:9 TestConstructorImportsRemainAvailableInEditor
from "@std/collections.ms" import SetBuilder
from "@std/csv.ms" import CsvOptions

def example() -> Unit:
    SetBuilder[String]()
    CsvOptions(delimiter: ",", line_ending: "\n")
