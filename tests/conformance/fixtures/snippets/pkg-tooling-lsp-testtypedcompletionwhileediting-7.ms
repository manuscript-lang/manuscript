# conform: tags=parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:134 TestTypedCompletionWhileEditing
type Point:
    x: Int
    y: String
fn read(point: Point) Int:
    return point.|
