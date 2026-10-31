# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:26 TestLocalExtensionCompletionAndNavigation
import Box from "./domain.ms"
import read from "./extension.ms"

fn use(value: Box) Int:
    return value.value
