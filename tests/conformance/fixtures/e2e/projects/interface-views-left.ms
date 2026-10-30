# conform: tags=closures,control-flow,diagnostics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/interface_views/left.ms
import Read, Reader from "./domain.ms"

impl Read for Reader:
    fn read() Int: self.operation() + 10

export fn left() Read:
    let value = 1
    return Read(Reader(fn() Int: value))
