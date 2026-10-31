type Bag:
    items: List[Int]

interface Picker:
    fn mapped[U](transform: fn(Int) U) List[U]

impl Picker for Bag:
    fn mapped(transform: fn(Int) Int) List[Int]:
        return self.items

export fn main() Int:
    return 0
