# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/analysis_test.go:192 TestLibraryProjectOverlaysAndManifestChanges
import value from "@lib/value.ms"

export fn other() Int: return value()
