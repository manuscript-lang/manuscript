from "./domain.ms" import Read, Reader

impl Read for Reader:
    def read() -> Int: self.operation() + 10

export def left() -> Read:
    let value = 1
    return Reader(lambda () -> Int: value)
