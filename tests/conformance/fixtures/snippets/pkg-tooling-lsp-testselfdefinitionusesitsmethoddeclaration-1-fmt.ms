# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/analysis_test.go:50 TestSelfDefinitionUsesItsMethodDeclaration
interface Read:
    def get() -> Int

type Box:
    value: Int

impl Read for Box:
    def get() -> Int:
        return self.value
