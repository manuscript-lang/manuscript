# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
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
