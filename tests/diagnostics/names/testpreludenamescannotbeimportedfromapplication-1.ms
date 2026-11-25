// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:137 TestPreludeNamesCannotBeImportedFromApplicationModules
import List from "./local.ms"

fn f() Int => List(1).value
// expect-error: MS2002 4:1 cannot find module ./local.ms (looked for local.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
