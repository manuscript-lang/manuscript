# conform: tags=control-flow,formatter,modules,optional,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/read_line_tail_test.go:40 TestReadLineCallableAliasFallback
import {read_line, ReadStream} from "@std/io.ms"

fn probe(input: ReadStream) Bool:
    let next = read_line
    if let line = next(input):
        return line.is_some()

    return false
