// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/local_extensions_test.go:53 TestLocalExtensionBoundaries
import loaded from "./extension.ms"
// expect-error: MS2002 4:1 cannot find module ./extension.ms (looked for extension.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
