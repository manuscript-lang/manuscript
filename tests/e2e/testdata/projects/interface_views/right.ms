from "./domain.ms" import Read, Reader

impl Read for Reader:
    def read() -> Int: self.operation() + 20

export def right() -> Read:
    let value = 2
    return Read(Reader(lambda () -> Int: value))
