# conform: tags=formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/read_line_tail_test.go:24 TestReadLinePresenceTailSelection
def probe(input: ReadStream, visits: List[Int]) -> Bool: ...
