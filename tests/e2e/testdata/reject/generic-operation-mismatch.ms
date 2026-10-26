type Bag:
    items: List[Int]

interface Picker:
    def mapped[U](transform: Callable[[Int], U]) -> List[U]

impl Picker for Bag:
    def mapped(transform: Callable[[Int], Int]) -> List[Int]:
        return self.items

export def main() -> Int:
    return 0
