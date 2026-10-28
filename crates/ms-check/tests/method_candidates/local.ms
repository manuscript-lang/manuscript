from "owner.ms" import Item

interface Read:
    def read() -> Int

impl Read for Item:
    def read() -> Int:
        return self.value

export def local(x: Item) -> Int:
    return x.read() + x.owned()
