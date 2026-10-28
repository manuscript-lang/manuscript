type Bag:
    items: List[Int]

interface Picker:
    fn mapped[U](transform: fn(Int) U) List[U]

impl Picker for Bag:
    fn mapped[U](transform: fn(Int) U) List[U]:
        var out: List[U] = []
        for x in self.items:
            out.append(transform(x))
        return out

export fn main() Int:
    let picker: Picker = Bag(items: [1])
    return 0
