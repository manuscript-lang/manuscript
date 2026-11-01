# conform: tags=formatter,modules,parser,stdlib-collections,stdlib-csv,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/constructor_imports_test.go:9 TestConstructorImportsRemainAvailableInEditor
import Partition from "@std/collections/collections.ms"
import CsvOptions from "@std/data/csv.ms"

fn example() Unit:
    Set[String]()
    CsvOptions(delimiter: ",", line_ending: "\n")
