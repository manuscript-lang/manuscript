# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/prelude_test.go:137 TestPreludeNamesCannotBeImportedFromApplicationModules
import List from "./local.ms"

fn f() Int: List(1).value
