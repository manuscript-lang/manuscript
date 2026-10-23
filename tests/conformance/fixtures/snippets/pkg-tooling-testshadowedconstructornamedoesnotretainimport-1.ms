# conform: tags=closures,diagnostics,modules,stdlib-csv,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/constructor_imports_test.go:35 TestShadowedConstructorNameDoesNotRetainImport
import CsvOptions from "@std/csv.ms"

fn example(CsvOptions: fn() Unit) Unit:
    CsvOptions()
