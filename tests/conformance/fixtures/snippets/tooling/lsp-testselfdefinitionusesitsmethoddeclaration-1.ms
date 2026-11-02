# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/analysis_test.go:50 TestSelfDefinitionUsesItsMethodDeclaration
interface Read:
    fn get() Int

type Box:
    value: Int

impl Read for Box:
    fn get() Int:
        return self.value
