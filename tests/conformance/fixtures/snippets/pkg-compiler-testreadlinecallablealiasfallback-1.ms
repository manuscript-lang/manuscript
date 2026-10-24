# conform: tags=control-flow,diagnostics,modules,optional,stdlib-io,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/read_line_tail_test.go:40 TestReadLineCallableAliasFallback
from "@std/io.ms" import read_line, ReadStream

def probe(input: ReadStream) -> Bool:
    let next = read_line
    if let line = next(input):
        return line.is_some()

    return False
