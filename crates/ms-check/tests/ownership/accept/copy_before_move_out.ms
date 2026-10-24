type Box:
    items: List[Int]

def items_of(b: Box) -> List[Int]:
    return b.items.clone()
