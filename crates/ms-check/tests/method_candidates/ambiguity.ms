interface First:
    fn read() Int

interface Second:
    fn read() Int

type Item:
    value: Int

impl Second for Item:
    fn read() Int:
        return self.value

impl First for Item:
    fn read() Int:
        return self.value

fn exercise(x: Item) Int:
    return x.read()
