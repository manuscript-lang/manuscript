# conform: tags=closures,formatter,modules,parser,stdlib-csv,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/constructor_imports_test.go:35 TestShadowedConstructorNameDoesNotRetainImport
import CsvOptions from "@std/csv.ms"

fn example(CsvOptions: fn() Unit) Unit:
    CsvOptions()
