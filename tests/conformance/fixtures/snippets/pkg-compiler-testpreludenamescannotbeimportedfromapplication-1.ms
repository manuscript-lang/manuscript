# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/prelude_test.go:137 TestPreludeNamesCannotBeImportedFromApplicationModules
from "./local.ms" import List

def f() -> Int: List(1).value
