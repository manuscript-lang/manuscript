# conform: tags=closures,control-flow,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/interface_views/left.ms
from "./domain.ms" import Read, Reader

impl Read for Reader:
    def read() -> Int: self.operation() + 10

export def left() -> Read:
    let value = 1
    return Read(Reader(lambda () -> Int: value))
