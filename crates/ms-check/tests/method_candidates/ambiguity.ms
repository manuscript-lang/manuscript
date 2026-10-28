interface First:
    def read() -> Int

interface Second:
    def read() -> Int

type Item:
    value: Int

impl Second for Item:
    def read() -> Int:
        return self.value

impl First for Item:
    def read() -> Int:
        return self.value

def exercise(x: Item) -> Int:
    return x.read()
