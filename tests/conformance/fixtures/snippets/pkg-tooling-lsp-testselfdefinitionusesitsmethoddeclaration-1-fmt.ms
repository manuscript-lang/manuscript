# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/analysis_test.go:50 TestSelfDefinitionUsesItsMethodDeclaration
interface Read:
    fn get() Int

type Box:
    value: Int

impl Read for Box:
    fn get() Int:
        return self.value
