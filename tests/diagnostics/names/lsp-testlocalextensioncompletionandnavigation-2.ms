// conform: tags=diagnostics,formatter,modules,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/completion_test.go:26 TestLocalExtensionCompletionAndNavigation
import (
	Box from "./domain.ms",
	read from "./extension.ms",
)

fn use(value Box) Int {
	return value.value
}
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
