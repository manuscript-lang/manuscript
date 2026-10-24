type Bag:
    items: List[Int]

export def main() -> Int:
    var bag = Bag(items: [])
    let add = bag.items.append  # error: must come from a variable
    add(1)
    return 0
