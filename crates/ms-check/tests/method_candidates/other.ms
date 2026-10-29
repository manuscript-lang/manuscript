import Item from "owner.ms"

interface Read:
    fn read() Int

impl Read for Item:
    fn read() Int:
        return self.value

export fn local(x: Item) Int:
    return x.read() + x.owned()
