import Read, Reader from "./domain.ms"

impl Read for Reader:
    fn read() Int: self.operation() + 10

export fn left() Read:
    let value = 1
    return Reader(fn() Int: value)
