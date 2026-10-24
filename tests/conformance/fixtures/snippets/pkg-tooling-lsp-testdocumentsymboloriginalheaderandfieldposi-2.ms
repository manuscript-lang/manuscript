# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/position_consumers_test.go:61 TestDocumentSymbolOriginalHeaderAndFieldPositions
# α😀
interface Read:
    def get() -> Int

type Box:
    value: Int  # 😀é

impl Read for Box:
    def get() -> Int:
        return self.value

def neighbor() -> Int: 1
