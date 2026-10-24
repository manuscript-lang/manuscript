# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/analysis_test.go:192 TestLibraryProjectOverlaysAndManifestChanges
from "@lib/value.ms" import value

export def other() -> Int: return value()
