import {Read, Reader} from "./domain.ms"

impl Read for Reader:
    fn read() Int: self.operation() + 20

export fn right() Read:
    let value = 2

    return Read(Reader(fn() Int: value))
