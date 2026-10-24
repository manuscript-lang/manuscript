# conform: tags=closures,control-flow,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/interface_views/right.ms
from "./domain.ms" import Read, Reader

impl Read for Reader:
    def read() -> Int: self.operation() + 20

export def right() -> Read:
    let value = 2
    return Read(Reader(lambda () -> Int: value))
