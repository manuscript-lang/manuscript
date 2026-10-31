# conform: tags=closures,control-flow,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/interface_views/right.ms
import Read, Reader from "./domain.ms"

impl Read for Reader:
    fn read() Int: self.operation() + 20

export fn right() Read:
    let value = 2
    return Read(Reader(fn() Int: value))
