# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:137 TestPreludeNamesCannotBeImportedFromApplicationModules
import List from "./local.ms"
fn f() Int: List(1).value
