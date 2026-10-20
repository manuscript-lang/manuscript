# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/position_consumers_test.go:61 TestDocumentSymbolOriginalHeaderAndFieldPositions
# α😀
interface Read:
    fn get() Int
type Box:
    value: Int # 😀é
impl Read for Box:
    fn get() Int:
        return self.value
fn neighbor() Int: 1
