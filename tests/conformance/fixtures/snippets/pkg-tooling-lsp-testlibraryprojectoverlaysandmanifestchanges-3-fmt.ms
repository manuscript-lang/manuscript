# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/analysis_test.go:192 TestLibraryProjectOverlaysAndManifestChanges
from "@lib/value.ms" import value

export def other() -> Int: return value()
