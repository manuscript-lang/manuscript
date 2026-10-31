# conform: tags=control-flow,faults,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:17 TestLocalExtensionCompletionAndNavigation
import Box from "./domain.ms"

interface Read:
    fn get() Int

impl Read for Box:
    fn get() Int:
        return self.value

export fn read(value: Box) Int:
    return value.get()
