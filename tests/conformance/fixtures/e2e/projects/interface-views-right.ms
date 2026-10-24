# conform: tags=closures,control-flow,diagnostics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/interface_views/right.ms
from "./domain.ms" import Read, Reader

impl Read for Reader:
    def read() -> Int: self.operation() + 20

export def right() -> Read:
    let value = 2
    return Read(Reader(lambda () -> Int: value))
