# conform: tags=closures,control-flow,diagnostics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/interface_views/left.ms
from "./domain.ms" import Read, Reader

impl Read for Reader:
    def read() -> Int: self.operation() + 10

export def left() -> Read:
    let value = 1
    return Read(Reader(lambda () -> Int: value))
