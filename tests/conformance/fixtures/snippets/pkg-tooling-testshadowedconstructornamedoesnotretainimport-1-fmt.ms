# conform: tags=closures,formatter,modules,parser,stdlib-csv,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/constructor_imports_test.go:35 TestShadowedConstructorNameDoesNotRetainImport
from "@std/csv.ms" import CsvOptions

def example(CsvOptions: Callable[[], Unit]) -> Unit:
    CsvOptions()
