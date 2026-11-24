// conform: tags=diagnostics,faults,optional,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/lsp/completion_test.go:109 TestPreludeNavigationUsesStandardSource
import panic from "@std/core.ms"

fn work(value Int?) Int!:
	return ok(value: value or panic("called Optional.get() on null"))
