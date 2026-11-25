// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/analysis_test.go:192 TestLibraryProjectOverlaysAndManifestChanges
import value from "@lib/value.ms"

export fn other() Int => return value()
// expect-error: MS2002 4:1 unknown import alias @lib; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
