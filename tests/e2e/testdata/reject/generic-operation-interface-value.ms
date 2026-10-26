type Bag:
    items: List[Int]

interface Picker:
    def mapped[U](transform: Callable[[Int], U]) -> List[U]

impl Picker for Bag:
    def mapped[U](transform: Callable[[Int], U]) -> List[U]:
        var out: List[U] = []
        for x in self.items:
            out.append(transform(x))
        return out

export def main() -> Int:
    let picker: Picker = Bag(items: [1])
    return 0
