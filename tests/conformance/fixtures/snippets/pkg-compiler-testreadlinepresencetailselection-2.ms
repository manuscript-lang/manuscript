# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/read_line_tail_test.go:24 TestReadLinePresenceTailSelection
def probe(input: ReadStream, visits: List[Int]) -> Bool: ...
